import AVFoundation
import Foundation

enum DictationOutcome: Equatable {
    case inserted, copied(reason: String), noAudio, noSpeech, failed(String), cancelled
}

struct DictationAudioLevel {
    let rms: Float
    let peak: Float
    static let empty = Self(samples: [])
    init(samples: [Float]) {
        rms = samples.isEmpty ? 0 : sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        peak = samples.reduce(0) { max($0, abs($1)) }
    }
    var isSilent: Bool { peak == 0 }
    var normalized: Float { rms > 0 ? min(1, max(0, (20 * log10(rms) + 60) / 60)) : 0 }
}

/// Timestamped samples distinguish a quiet microphone from a stopped callback.
struct DictationAudioHistory {
    private var history: [Float] = []
    private var lastInput: TimeInterval?
    private var lastSignal: TimeInterval?
    mutating func receive(_ level: DictationAudioLevel, at now: TimeInterval) {
        if let lastInput, now - lastInput > 0.4 { history.removeAll(keepingCapacity: true) }
        lastInput = now
        if !level.isSilent { lastSignal = now }
        history.append(level.normalized)
        if history.count > 20 { history.removeFirst(history.count - 20) }
    }
    func levels(at now: TimeInterval) -> [Float] {
        guard let lastInput, now - lastInput <= 0.4 else { return [] }
        return history
    }
    func hasRecentAudio(at now: TimeInterval) -> Bool {
        guard let lastSignal else { return false }
        return now - lastSignal < 3
    }
}

struct DictationRun {
    private var generation = 0
    private var active = false
    mutating func begin() -> Int { generation += 1; active = true; return generation }
    mutating func cancel() { generation += 1; active = false }
    func accepts(_ token: Int) -> Bool { active && token == generation }
}

struct DictationTranscript {
    let language: String
    private var finals: [String] = []
    private var draft = ""
    init(language: String) { self.language = language }
    mutating func receive(_ text: String, final: Bool) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if final { if !clean.isEmpty { finals.append(clean) }; draft = "" } else { draft = clean }
        return (finals + [draft]).filter { !$0.isEmpty }.joined(separator: joiner(for: language))
    }
}

/// Work dictation uses original-language recognition only: no translation, voice
/// output, virtual mic switching, or meeting records.
@MainActor final class DictationEngine: ObservableObject {
    enum Phase { case idle, preparing, recording, finishing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var text = ""
    @Published private(set) var lastText = ""
    @Published var message = ""
    private(set) var outcome: DictationOutcome?
    private(set) var runID = 0
    var onComplete: ((String) -> Bool)?
    var onChange: (() -> Void)?
    var busy: Bool { phase != .idle }
    private var run = DictationRun()
    private var transcript = DictationTranscript(language: "en")
    private var source: AudioSource?
    private var stream: RecognitionStream?
    private var reader: Task<Void, Never>?
    private var preparation: Task<Void, Never>?
    private var limit: Task<Void, Never>?
    private var destination: DictationPaste?
    private(set) var lastDeliveryDiagnostics: [String: Any] = [:]
    var deliveryDiagnostics: [String: Any] { destination?.diagnostics ?? lastDeliveryDiagnostics }
    private let queue = DispatchQueue(label: "com.wquguru.cicada.dictation.audio")
    private var audioStats = DictationAudioStats()
    var audioDiagnostics: [String: Any] { audioStats.snapshot() }
    var audioLevels: [Float] { audioStats.levels }
    var hasAudio: Bool { audioStats.hasAudio }
    var hasRecentAudio: Bool { audioStats.hasRecentAudio }

    private let recognize: @MainActor (String) async throws -> RecognitionStream

    init(recognize: @escaping @MainActor (String) async throws -> RecognitionStream) {
        self.recognize = recognize
    }
    convenience init() {
        self.init { locale in
            guard await Recognition.authorize() else { throw Recognition.notAllowed }
            try await Recognition.install(locale) { _ in }
            return try await Recognition.start(locale, drafts: true, speaking: false)
        }
    }

    func start(locale: String, device: OutputDevice?, file: URL? = nil) {
        guard !busy else { return }
        destination = DictationPaste()
        lastDeliveryDiagnostics = [:]
        let token = run.begin()
        currentToken = token
        runID += 1
        outcome = nil
        transcript = DictationTranscript(language: Locale(identifier: locale).languageCode ?? "en")
        text = ""
        message = ""
        audioStats = DictationAudioStats()
        debugLog("dictation: preparing locale=\(locale)")
        phase = .preparing
        onChange?()
        preparation = Task { [weak self] in
            guard let self else { return }
            do {
                if file == nil {
                    var allowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                    if !allowed { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
                    guard allowed else { throw Self.problem(L("请允许麦克风访问")) }
                }
                let input = try await self.recognize(locale)
                guard !Task.isCancelled, self.run.accepts(token) else { await input.cancel(); return }
                self.stream = input
                self.reader = Task { [weak self] in
                    do {
                        for try await piece in input.results {
                            guard let self, self.run.accepts(token) else { return }
                            self.text = self.transcript.receive(piece.text, final: piece.isFinal)
                            self.onChange?()
                        }
                    } catch {
                        guard let self, self.run.accepts(token) else { return }
                        self.cancel(outcome: .failed(error.localizedDescription))
                    }
                }
                let microphone: AudioSource
                if let file { microphone = try DictationFileSource(file) }
                else { microphone = RoomMic(device: device) }
                self.source = microphone
                let converter = PCMConverter()
                let audioQueue = self.queue
                let audioStats = self.audioStats
                microphone.onAudio = { buffer in
                    audioQueue.async {
                        let converted = converter.convert(buffer, to: input.format)
                        audioStats.receive(buffer, submitted: converted?.frameLength ?? 0)
                        if let converted { input.append(converted) }
                    }
                }
                if let fileSource = microphone as? DictationFileSource {
                    fileSource.onEnd = { [weak self] in Task { @MainActor in
                        guard let self, self.run.accepts(token) else { return }; self.stop()
                    } }
                }
                self.phase = .recording
                try microphone.start()
                debugLog("dictation: recording")
                self.limit = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(120)) } catch { return }
                    guard let self, self.run.accepts(token) else { return }; self.stop()
                }
                self.onChange?()
            } catch {
                guard self.run.accepts(token) else { return }
                self.cancel(outcome: .failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        guard phase == .recording, let input = stream else { return }
        phase = .finishing
        limit?.cancel(); limit = nil
        source?.stop(); source = nil
        let token = currentToken
        let finishingReader = reader
        onChange?()
        Task { [weak self] in
            guard let self else { return }
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in self.queue.async { done.resume() } }
            // A stalled service must not leave the work shortcut stuck forever.
            let timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.run.accepts(token) else { return }
                self.cancel(outcome: .failed(L("听写超时，请重试")))
            }
            await input.finish()
            await finishingReader?.value
            timeout.cancel()
            guard self.run.accepts(token) else { return }
            let result = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastText = result
            self.phase = .idle
            self.run.cancel()
            self.stream = nil; self.reader = nil
            if result.isEmpty {
                self.message = L("没有听到语音")
                self.outcome = self.hasAudio ? .noSpeech : .noAudio
                self.lastDeliveryDiagnostics = ["reason": "empty_transcript"]
            }
            else {
                let pasted = self.onComplete?(result) ?? self.destination?.deliver(result) ?? false
                self.lastDeliveryDiagnostics = self.destination?.diagnostics ?? ["reason": "destination_missing"]
                self.message = pasted ? L("已输入") : L("已复制，请粘贴到输入框")
                self.outcome = pasted ? .inserted : .copied(reason: self.lastDeliveryDiagnostics["reason"] as? String ?? "destination_missing")
            }
            self.destination = nil
            debugLog("dictation: finished chars=\(result.count) audio=\(self.audioDiagnostics)")
            debugLog("dictation delivery: \(self.lastDeliveryDiagnostics)")
            self.onChange?()
        }
    }

    private var currentToken = 0

    func cancel() { cancel(outcome: .cancelled) }

    private func cancel(outcome: DictationOutcome) {
        run.cancel()
        preparation?.cancel(); preparation = nil
        limit?.cancel(); limit = nil
        source?.stop(); source = nil
        let input = stream
        stream = nil
        reader?.cancel(); reader = nil
        if let input { Task { await input.cancel() } }
        destination = nil
        phase = .idle
        self.outcome = outcome
        if case .failed(let detail) = outcome { message = detail }
        else { message = L("已取消听写") }
        onChange?()
    }

    static func problem(_ message: String) -> NSError {
        NSError(domain: "Dictation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Per-run counters let diagnostics distinguish a missing key event from an empty microphone.
private final class DictationAudioStats: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers = 0
    private var captured = 0
    private var submitted = 0
    private var peak: Float = 0
    private var history = DictationAudioHistory()
    var levels: [Float] { lock.withLock { history.levels(at: ProcessInfo.processInfo.systemUptime) } }
    var hasRecentAudio: Bool { lock.withLock { history.hasRecentAudio(at: ProcessInfo.processInfo.systemUptime) } }
    var hasAudio: Bool { lock.withLock { peak > 0 } }

    func receive(_ buffer: AVAudioPCMBuffer, submitted frames: AVAudioFrameCount) {
        let level: DictationAudioLevel
        if let samples = buffer.floatChannelData?[0] {
            level = DictationAudioLevel(samples: Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))))
        } else { level = .empty }
        lock.withLock {
            buffers += 1; captured += Int(buffer.frameLength); submitted += Int(frames)
            peak = max(peak, level.peak)
            history.receive(level, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    func snapshot() -> [String: Any] {
        lock.withLock { ["buffers": buffers, "capturedFrames": captured, "submittedFrames": submitted, "peak": peak] }
    }
}

/// The dev command feeds a real local file through exactly the microphone path.
private final class DictationFileSource: AudioSource, @unchecked Sendable {
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    var onEnd: (() -> Void)?
    private let file: AVAudioFile
    private let lock = NSLock()
    private var stopped = false
    init(_ url: URL) throws { file = try AVAudioFile(forReading: url) }
    func start() throws {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            while !lock.withLock({ stopped }), file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { break }
                do { try file.read(into: buffer) } catch { break }
                guard buffer.frameLength > 0 else { break }
                onAudio?(buffer)
                Thread.sleep(forTimeInterval: Double(buffer.frameLength) / file.processingFormat.sampleRate)
            }
            if !lock.withLock({ stopped }) { onEnd?() }
        }
    }
    func stop() { lock.withLock { stopped = true } }
}
