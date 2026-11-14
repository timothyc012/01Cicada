import Foundation
import Darwin

/// Versioned text-only records consumed read-only by AWhisper.
struct DictationHistoryEntry: Codable, Identifiable, Equatable {
    var schemaVersion = 1
    let id: String
    let timestamp: Int64
    let language: String
    let text: String
}

final class DictationHistoryStore {
    let root: URL
    init(root: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.root = root ?? support.appendingPathComponent("\(DevBuild.supportFolder)/Dictations", isDirectory: true)
    }
    @discardableResult
    func append(text: String, language: String, at date: Date = Date()) throws -> DictationHistoryEntry? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let entry = DictationHistoryEntry(id: UUID().uuidString, timestamp: Int64(date.timeIntervalSince1970), language: language, text: text)
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = root.appendingPathComponent(".\(entry.id).tmp")
        let destination = root.appendingPathComponent("\(entry.id).json")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try file.write(contentsOf: JSONEncoder().encode(entry))
            try file.synchronize(); try file.close()
            try manager.moveItem(at: temporary, to: destination)
        } catch {
            try? file.close(); try? manager.removeItem(at: temporary)
            throw error
        }
        return entry
    }
    func entries() throws -> [DictationHistoryEntry] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return [] }
        let files = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        return files.compactMap { url -> DictationHistoryEntry? in
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 1_048_576,
                  let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(DictationHistoryEntry.self, from: data),
                  record.schemaVersion == 1, UUID(uuidString: record.id) != nil,
                  url.lastPathComponent == "\(record.id).json", !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return record
        }.sorted { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp > $1.timestamp }
    }
}
