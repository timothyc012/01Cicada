import Foundation
import Testing
@testable import Cicada

@Suite struct DictationHistoryTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("cicada-history-\(UUID().uuidString)") }
    @Test func completedTextSurvivesRestartAndKeepsLanguageAndTime() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationHistoryStore(root: root)
        let entry = try #require(try store.append(text: "  안녕하세요\n", language: "ko-KR", at: Date(timeIntervalSince1970: 123)))
        let reloaded = try DictationHistoryStore(root: root).entries()
        #expect(reloaded == [entry]); #expect(entry.text == "안녕하세요"); #expect(entry.language == "ko-KR"); #expect(entry.timestamp == 123)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("\(entry.id).json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let data = try Data(contentsOf: root.appendingPathComponent("\(entry.id).json"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
    }
    @Test func emptyRecognitionDoesNotCreateARecordAndIdenticalPhrasesRemainSeparate() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationHistoryStore(root: root)
        #expect(try store.append(text: "\n ", language: "en-US") == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let first = try #require(try store.append(text: "yes", language: "en-US"))
        let second = try #require(try store.append(text: "yes", language: "en-US"))
        #expect(first.id != second.id); #expect(try store.entries().count == 2)
    }
    @Test func malformedSiblingDoesNotHideSavedTextAndWriteFailureIsReported() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationHistoryStore(root: root)
        _ = try store.append(text: "safe", language: "en-US")
        try Data("{".utf8).write(to: root.appendingPathComponent("bad.json"))
        #expect(try store.entries().count == 1)
        let blocker = root.appendingPathComponent("not-a-folder")
        try Data().write(to: blocker)
        #expect(throws: (any Error).self) { try DictationHistoryStore(root: blocker).append(text: "must not disappear", language: "en-US") }
    }
    @MainActor @Test func engineRestoresLastSavedTextWithoutOpeningMicrophone() throws {
        let root = root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationHistoryStore(root: root)
        _ = try store.append(text: "restored", language: "en-US")
        let engine = DictationEngine(recognize: { _ in throw DictationEngine.problem("unused") }, history: store)
        #expect(engine.lastText == "restored"); #expect(engine.phase == .idle)
    }
}
