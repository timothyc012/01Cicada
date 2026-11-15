import Foundation
import AppKit
import AVFoundation
import Testing
@testable import Cicada

@Suite struct DictationTests {
    @Test func partialsReplaceAndFinalsAccumulate() {
        var text = DictationTranscript(language: "ko")
        #expect(text.receive("안녕", final: false) == "안녕")
        #expect(text.receive("안녕하세요.", final: true) == "안녕하세요.")
        #expect(text.receive("오늘", final: false) == "안녕하세요. 오늘")
        #expect(text.receive("오늘 회의입니다.", final: true) == "안녕하세요. 오늘 회의입니다.")
        #expect(text.receive("", final: true) == "안녕하세요. 오늘 회의입니다.")
    }
    @Test func chinesePhrasesDoNotGainSpaces() {
        var text = DictationTranscript(language: "zh-CN")
        _ = text.receive("你好。", final: true)
        #expect(text.receive("今天开会。", final: true) == "你好。今天开会。")
    }
    @Test func cancelledRecognitionCannotCompleteANewerRecording() {
        var run = DictationRun()
        let old = run.begin()
        run.cancel()
        #expect(!run.accepts(old))
        let next = run.begin()
        #expect(!run.accepts(old))
        #expect(run.accepts(next))
    }
    @Test func pasteRequiresTheOriginalAppAndField() {
        #expect(DictationPastePolicy.canPaste(target: 11, current: 11, sameField: true, trusted: true))
        #expect(!DictationPastePolicy.canPaste(target: 11, current: 12, sameField: true, trusted: true))
        #expect(!DictationPastePolicy.canPaste(target: 11, current: 11, sameField: false, trusted: true))
        #expect(!DictationPastePolicy.canPaste(target: 11, current: 11, sameField: true, trusted: false))
        #expect(!DictationPastePolicy.canPaste(target: nil, current: nil, sameField: true, trusted: true))
    }
    @Test func pasteBlockReasonAllowsTheOriginalAppAndField() {
        #expect(DictationPastePolicy.blockReason(target: 11, current: 11, sameField: true, trusted: true) == nil)
    }
    @Test func pasteBlockReasonIdentifiesMissingAccessibility() {
        #expect(DictationPastePolicy.blockReason(target: 11, current: 11, sameField: true, trusted: false) == "accessibility_denied")
    }
    @Test func pasteBlockReasonIdentifiesMissingDestination() {
        #expect(DictationPastePolicy.blockReason(target: nil, current: 11, sameField: true, trusted: true) == "no_destination_app")
        #expect(DictationPastePolicy.blockReason(target: nil, current: nil, sameField: true, trusted: true) == "no_destination_app")
    }
    @Test func pasteBlockReasonIdentifiesChangedOrClosedApplication() {
        #expect(DictationPastePolicy.blockReason(target: 11, current: 12, sameField: true, trusted: true) == "application_changed")
        #expect(DictationPastePolicy.blockReason(target: 11, current: nil, sameField: true, trusted: true) == "application_changed")
        #expect(DictationPastePolicy.blockReason(target: 11, current: 12, sameField: false, trusted: true) == "application_changed")
    }
    @Test func pasteBlockReasonIdentifiesChangedFocusedField() {
        #expect(DictationPastePolicy.blockReason(target: 11, current: 11, sameField: false, trusted: true) == "focused_field_changed")
        // An app that won't say which field has focus (Electron): same app all along, so it pastes.
        #expect(DictationPastePolicy.blockReason(target: 11, current: 11, sameField: false, trusted: true, fieldUnknown: true) == nil)
        #expect(DictationPastePolicy.blockReason(target: 11, current: 12, sameField: false, trusted: true, fieldUnknown: true) == "application_changed")
        #expect(DictationPastePolicy.blockReason(target: 11, current: 11, sameField: false, trusted: false, fieldUnknown: true) == "accessibility_denied")
    }
    @Test func pasteBlockReasonPreservesTheExistingSafetyPolicy() {
        let processes: [pid_t?] = [nil, 11, 12]
        for target in processes {
            for current in processes {
                for sameField in [false, true] {
                    for trusted in [false, true] {
                        let reason = DictationPastePolicy.blockReason(target: target, current: current, sameField: sameField, trusted: trusted)
                        #expect((reason == nil) == DictationPastePolicy.canPaste(target: target, current: current, sameField: sameField, trusted: trusted))
                    }
                }
            }
        }
    }
    @MainActor @Test func interpretingRehearsalCannotStartWhileDictating() async {
        let settings = AppSettings()
        let speak = SpeakEngine(settings: settings, voiceMic: VoiceMic())
        let tester = SpeakTester(speak: speak, ling: LingClient(), settings: settings)
        tester.canStart = { false }
        tester.start(.voice)
        tester.start(.sample)
        await Task.yield()
        #expect(tester.phase == .idle)
        #expect(!tester.busy)
    }
    @MainActor @Test func delayedPasteStillReadsDictation() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("previous unrelated clipboard", forType: .string)
        DictationPaste.copy("dictated words", to: board)
        try await Task.sleep(for: .milliseconds(850))
        #expect(board.string(forType: .string) == "dictated words")
    }
}

private final class ControlledDictationStream: RecognitionStream, @unchecked Sendable {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let results: AsyncThrowingStream<Recognition.Piece, Error>
    let output: AsyncThrowingStream<Recognition.Piece, Error>.Continuation
    private let finishSignal: AsyncStream<Void>
    private let finishOutput: AsyncStream<Void>.Continuation
    init() {
        (results, output) = AsyncThrowingStream.makeStream()
        (finishSignal, finishOutput) = AsyncStream.makeStream()
    }
    func append(_ buffer: AVAudioPCMBuffer) {}
    func finalize(through seconds: Double) async throws {}
    func finish() async { for await _ in finishSignal { break }; output.finish() }
    func cancel() async { output.finish() }
    func releaseFinish() { finishOutput.yield(()); finishOutput.finish() }
    func say(_ text: String) { output.yield(.init(text: text, isFinal: true, start: 0, end: 1)) }
}

extension DictationTests {
    @MainActor @Test func oldFinishCannotPasteAfterCancelAndRestart() async throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000)!
        audio.frameLength = 32000
        audio.floatChannelData![0].initialize(repeating: 0, count: 32000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: audio)
        let old = ControlledDictationStream(), next = ControlledDictationStream()
        var calls = 0
        let historyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("history-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: historyRoot) }
        let history = DictationHistoryStore(root: historyRoot)
        let engine = DictationEngine(recognize: { _ in calls += 1; return calls == 1 ? old : next }, history: history)
        defer { engine.cancel() }
        var inserted: [String] = []
        engine.onComplete = { inserted.append($0); return true }
        func wait(_ phase: DictationEngine.Phase) async throws {
            for _ in 0..<200 {
                if engine.phase == phase { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("Dictation did not reach expected phase")
        }
        engine.start(locale: "en-US", device: nil, file: url)
        try await wait(.recording)
        old.say("old words")
        await Task.yield()
        engine.stop()
        engine.cancel()
        engine.start(locale: "en-US", device: nil, file: url)
        try await wait(.recording)
        old.releaseFinish()
        next.say("new words")
        await Task.yield()
        engine.stop()
        next.releaseFinish()
        try await wait(.idle)
        #expect(inserted == ["new words"])
        #expect(engine.lastText == "new words")
        #expect(try history.entries().map(\.text) == ["new words"])
    }
}


extension DictationTests {
    @MainActor @Test(arguments: [false, true]) func historyIsIndependentOfPasteAndWriteFailureDoesNotBlockDelivery(failSave: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-delivery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let historyRoot = root.appendingPathComponent("records")
        if failSave { try Data().write(to: historyRoot) }
        let history = DictationHistoryStore(root: historyRoot)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000)!
        audio.frameLength = 32000; audio.floatChannelData![0].initialize(repeating: 0, count: 32000)
        let file = root.appendingPathComponent("silent.wav")
        try AVAudioFile(forWriting: file, settings: format.settings).write(from: audio)
        let stream = ControlledDictationStream()
        let engine = DictationEngine(recognize: { _ in stream }, history: history)
        defer { engine.cancel() }
        var deliveries = 0
        engine.onComplete = { _ in deliveries += 1; return failSave }
        engine.start(locale: "de-DE", device: nil, file: file)
        for _ in 0..<200 { if engine.phase == .recording { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(engine.phase == .recording)
        stream.say("synthetic completion")
        for _ in 0..<100 { if engine.text == "synthetic completion" { break }; try await Task.sleep(for: .milliseconds(10)) }
        engine.stop(); stream.releaseFinish()
        for _ in 0..<200 { if engine.phase == .idle { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(engine.phase == .idle); #expect(deliveries == 1); #expect(engine.lastText == "synthetic completion")
        if failSave {
            #expect(engine.historyError != nil); #expect(engine.outcome == .inserted)
        } else {
            let entries = try history.entries()
            #expect(entries.count == 1); #expect(entries.first?.language == "de-DE")
            #expect(entries.first?.text == "synthetic completion"); #expect(engine.historyError == nil)
        }
    }
}


extension DictationTests {
    @MainActor @Test func emptyAttemptKeepsThePreviousSuccessfulTextAvailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = DictationHistoryStore(root: root); _ = try history.append(text: "previous successful words", language: "en-US")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32000)!
        audio.frameLength = 32000; audio.floatChannelData![0].initialize(repeating: 0, count: 32000)
        let file = root.appendingPathComponent("silent.wav"); try AVAudioFile(forWriting: file, settings: format.settings).write(from: audio)
        let stream = ControlledDictationStream(); let engine = DictationEngine(recognize: { _ in stream }, history: history)
        defer { engine.cancel() }
        var deliveries = 0; engine.onComplete = { _ in deliveries += 1; return false }
        engine.start(locale: "en-US", device: nil, file: file)
        for _ in 0..<200 { if engine.phase == .recording { break }; try await Task.sleep(for: .milliseconds(10)) }
        engine.stop(); stream.releaseFinish()
        for _ in 0..<200 { if engine.phase == .idle { break }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(engine.phase == .idle); #expect(deliveries == 0)
        #expect(engine.lastText == "previous successful words"); #expect(try history.entries().count == 1)
    }
}
