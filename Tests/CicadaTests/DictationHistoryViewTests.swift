import Foundation
import AppKit
import Testing
@testable import Cicada

@Suite struct DictationHistoryViewTests {
    @MainActor @Test func historyLoadsSavedTextFiltersAndCopiesWithoutAccessibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-history-view-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DictationHistoryStore(root: root)
        _ = try store.append(text: "먼저 말한 문장", language: "ko-KR", at: Date(timeIntervalSince1970: 10))
        let newest = try #require(try store.append(text: "Korrigierte Übersetzung", language: "de-DE", at: Date(timeIntervalSince1970: 20)))
        let model = DictationHistoryModel(store: store)
        model.reload()
        #expect(model.entries.count == 2); #expect(model.entries.first?.id == newest.id)
        model.query = "ubersetzung"; #expect(model.filteredEntries.map(\.id) == [newest.id])
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        #expect(model.copy(newest, to: board)); #expect(board.string(forType: .string) == newest.text)
        #expect(model.copiedID == newest.id)
    }
    @MainActor @Test func aReadFailureKeepsPreviouslyShownEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-history-error-\(UUID().uuidString)")
        let moved = root.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: moved) }
        let store = DictationHistoryStore(root: root); _ = try store.append(text: "keep me", language: "en-US")
        let model = DictationHistoryModel(store: store); model.reload(); #expect(model.entries.count == 1)
        try FileManager.default.moveItem(at: root, to: moved); try Data().write(to: root)
        model.reload(); #expect(model.entries.count == 1); #expect(model.errorMessage != nil)
    }
}
