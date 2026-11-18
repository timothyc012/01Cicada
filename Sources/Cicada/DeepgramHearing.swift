import AVFoundation
import Foundation

/// Deepgram's live speech recognition (nova-3 over a WebSocket), picked under Settings › AI 服务 ›
/// Deepgram: the meeting heard by Deepgram as it is spoken, drafts and all, instead of on this Mac.
/// Its own key (`AIKey` "deepgram"), sent only in the Authorization header to Deepgram's EU host.
enum Deepgram {
    static let keyName = "deepgram"
    static let host = "api.eu.deepgram.com"

    enum Failure: Error, Equatable {
        /// Deepgram said what went wrong (a bad key or parameter, its own trouble).
        case server(String)
        /// The connection closed while listening went on.
        case closed
    }

    /// `language`: the meeting's code ("ko", "ru", "zh-CN"); nil lets nova-3 hear several (`multi`).
    static func url(language: String?) -> URL {
        var c = URLComponents()
        c.scheme = "wss"
        c.host = host
        c.path = "/v1/listen"
        c.queryItems = [
            .init(name: "model", value: "nova-3"),
            .init(name: "language", value: language ?? "multi"),
            .init(name: "encoding", value: "linear16"),
            .init(name: "sample_rate", value: "16000"),
            .init(name: "channels", value: "1"),
            .init(name: "interim_results", value: "true"),
            .init(name: "smart_format", value: "true"),
            .init(name: "punctuate", value: "true"),
            // A pause this long ends the utterance (speech_final); UtteranceEnd catches the ones
            // background noise keeps open.
            .init(name: "endpointing", value: "450"),
            .init(name: "utterance_end_ms", value: "1200"),
        ]
        return c.url!
    }

    /// Whether Deepgram takes `key`: true, false (401/403: it doesn't), nil (no answer). The same
    /// listen socket a meeting opens (the EU host has no project API), closed at once with no audio.
    static func check(key: String, session: URLSession = .shared) async -> Bool? {
        var request = URLRequest(url: url(language: "en"))
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }
        let opened: Bool
        do {
            try await task.send(.string(#"{"type":"CloseStream"}"#))
            _ = try await task.receive()
            opened = true
        } catch {
            opened = false
        }
        let code = (task.response as? HTTPURLResponse)?.statusCode
        debugLog("deepgram: key check \(opened ? "opened" : "failed") HTTP \(code.map(String.init) ?? "-")")
        if opened || code == 101 { return true }
        return code == 401 || code == 403 ? false : nil
    }

    /// Chinese and Japanese lines join without spaces.
    static func spaced(_ language: String?) -> Bool {
        guard let language else { return true }
        return !(language.hasPrefix("zh") || language.hasPrefix("ja"))
    }
}

/// Deepgram's messages into what a `RecognitionStream` yields: drafts that cover the whole line so
/// far, and one finished line per utterance. Deepgram finalizes a few words at a time (`is_final`)
/// and marks the end of what was said (`speech_final`, `UtteranceEnd`, or `from_finalize` after a
/// Finalize); listening translates finished lines, so the pieces are kept until then.
struct DeepgramAssembler {
    let spaced: Bool
    /// A line no pause ends is cut after this long, so a speech without breaks still gets translated.
    static let longest = 20.0

    private var words: [String] = []
    private var start: Double?
    private var end = 0.0
    private var confidences: [Double] = []
    private var language: String?

    init(spaced: Bool) { self.spaced = spaced }

    mutating func take(_ data: Data) throws -> [Recognition.Piece] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String else { return [] }
        switch type {
        case "Results": return results(root)
        case "UtteranceEnd": return flush().map { [$0] } ?? []
        case "Error":
            let said = (root["description"] as? String) ?? (root["message"] as? String) ?? "error"
            throw Deepgram.Failure.server(said)
        default: return []
        }
    }

    /// Words heard and not yet given as a finished line, finished now (the stream is ending).
    mutating func flush() -> Recognition.Piece? {
        defer { words = []; start = nil; confidences = []; language = nil; draft = "" }
        let text = joined(words + (draft.isEmpty ? [] : [draft]))
        guard !text.isEmpty, let start else { return nil }
        let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
        return Recognition.Piece(text: text, isFinal: true, start: start, end: end, confidence: confidence, language: language)
    }

    /// The interim words after the last final ones.
    private var draft = ""

    private mutating func results(_ root: [String: Any]) -> [Recognition.Piece] {
        let alt = ((root["channel"] as? [String: Any])?["alternatives"] as? [[String: Any]])?.first
        let text = ((alt?["transcript"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let at = (root["start"] as? Double) ?? end
        let lasted = (root["duration"] as? Double) ?? 0
        let isFinal = root["is_final"] as? Bool ?? false
        let ends = (root["speech_final"] as? Bool ?? false) || (root["from_finalize"] as? Bool ?? false)
        if !text.isEmpty {
            if start == nil { start = at }
            end = max(end, at + lasted)
            if let heard = (alt?["languages"] as? [String])?.first { language = heard }
        }
        if isFinal {
            draft = ""
            if !text.isEmpty {
                words.append(text)
                if let c = alt?["confidence"] as? Double { confidences.append(c) }
            }
            if ends || (start.map { end - $0 >= Self.longest } ?? false) {
                return flush().map { [$0] } ?? []
            }
        } else {
            guard !text.isEmpty else { return [] }
            draft = text
        }
        let line = joined(words + (draft.isEmpty ? [] : [draft]))
        guard !line.isEmpty, let start else { return [] }
        return [Recognition.Piece(text: line, isFinal: false, start: start, end: end, confidence: nil, language: language)]
    }

    private func joined(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: spaced ? " " : "")
    }
}

/// The meeting heard by Deepgram as a `RecognitionStream`: audio goes out as 16 kHz 16-bit PCM over
/// the socket, drafts and finished lines come back. Any failure (a rejected key, the connection
/// dropping) ends `results` with an error, and listening goes back to this Mac.
/// No reconnect: a new socket restarts Deepgram's clock at zero.
final class DeepgramStream: RecognitionStream, @unchecked Sendable {
    let format: AVAudioFormat
    let results: AsyncThrowingStream<Recognition.Piece, Error>
    private let continuation: AsyncThrowingStream<Recognition.Piece, Error>.Continuation
    private let task: URLSessionWebSocketTask
    private let queue = DispatchQueue(label: "com.wquguru.cicada.deepgram")
    private var assembler: DeepgramAssembler
    /// finish() or cancel() was asked: a closing socket is then the end, not a failure.
    private var closing = false
    private var over = false
    private var lastSent = Date()
    private var keepAlive: Task<Void, Never>?

    /// `format`: the analyzer's, when it is 16 kHz mono 16-bit, so the audio held for it can be replayed.
    init(key: String, language: String?, format: AVAudioFormat? = nil, session: URLSession = .shared) {
        if let format, format.sampleRate == 16000, format.channelCount == 1, format.commonFormat == .pcmFormatInt16 {
            self.format = format
        } else {
            self.format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        }
        assembler = DeepgramAssembler(spaced: Deepgram.spaced(language))
        (results, continuation) = AsyncThrowingStream.makeStream()
        var request = URLRequest(url: Deepgram.url(language: language))
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        task = session.webSocketTask(with: request)
        task.resume()
        debugLog("deepgram: connecting (\(language ?? "multi"))")
        // Deepgram closes a socket that hears nothing for 10 s (NET-0001): KeepAlive every 4 s of quiet.
        // Started before receiving, so a connection that fails at once still cancels it.
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self else { return }
                let due = self.queue.sync { !self.over && Date().timeIntervalSince(self.lastSent) >= 4 }
                if due { self.sendText(#"{"type":"KeepAlive"}"#) }
            }
        }
        receive()
    }

    /// Dropped without finish() or cancel(): the socket (billed while open) closes with it.
    deinit {
        keepAlive?.cancel()
        task.cancel(with: .goingAway, reason: nil)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.int16ChannelData, buffer.frameLength > 0 else { return }
        let bytes = Data(bytes: data[0], count: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
        queue.async { [self] in
            guard !over, !closing else { return }
            lastSent = Date()
            task.send(.data(bytes)) { [weak self] error in
                if let error { self?.fail(error) }
            }
        }
    }

    func finalize(through seconds: Double) async throws {
        sendText(#"{"type":"Finalize"}"#)
    }

    func finish() async {
        queue.sync { closing = true }
        sendText(#"{"type":"Finalize"}"#, evenClosing: true)
        sendText(#"{"type":"CloseStream"}"#, evenClosing: true)
        // Deepgram answers with the last lines, then closes the socket; don't wait on it forever.
        for _ in 0..<30 {
            if queue.sync(execute: { over }) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        queue.sync { end(nil) }
        task.cancel(with: .normalClosure, reason: nil)
    }

    func cancel() async {
        queue.sync { closing = true }
        task.cancel(with: .normalClosure, reason: nil)
        queue.sync {
            guard !over else { return }
            over = true
            keepAlive?.cancel()
            continuation.finish()
        }
    }

    private func sendText(_ text: String, evenClosing: Bool = false) {
        queue.async { [self] in
            guard !over, evenClosing || !closing else { return }
            lastSent = Date()
            task.send(.string(text)) { [weak self] error in
                if let error { self?.fail(error) }
            }
        }
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let data: Data
                switch message {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: data = Data()
                }
                self.queue.async {
                    guard !self.over else { return }
                    do {
                        for piece in try self.assembler.take(data) { self.continuation.yield(piece) }
                    } catch {
                        self.end(error)
                        return
                    }
                }
                self.receive()
            case .failure(let error):
                self.queue.async {
                    // After CloseStream the socket closing is how Deepgram says it is done.
                    if self.closing { self.end(nil) } else { self.end(self.rejection ?? error) }
                }
            }
        }
    }

    /// The handshake's answer when the socket never opened (401: the key is wrong).
    private var rejection: Error? {
        guard let code = (task.response as? HTTPURLResponse)?.statusCode, code >= 400 else { return nil }
        return code == 401 || code == 403 ? LingClient.Failure.invalidKey : LingClient.Failure.http(code)
    }

    private func fail(_ error: Error) {
        queue.async { [self] in
            guard !closing else { return }
            end(rejection ?? error)
        }
    }

    /// On `queue`: the last words as a finished line, then `results` ends (with `error` if it failed).
    private func end(_ error: Error?) {
        guard !over else { return }
        over = true
        keepAlive?.cancel()
        if let last = assembler.flush() { continuation.yield(last) }
        if let error {
            // Deepgram says why in the close frame (1008 a bad request, 1011 NET-0001 no audio).
            let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            debugLog("deepgram: ended: \(error) close=\(task.closeCode.rawValue) \(reason)")
            continuation.finish(throwing: error)
        } else if !closing {
            continuation.finish(throwing: Deepgram.Failure.closed)
        } else {
            continuation.finish()
        }
        if !closing { task.cancel(with: .goingAway, reason: nil) }
    }
}
