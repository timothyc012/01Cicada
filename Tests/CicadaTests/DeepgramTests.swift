import Foundation
import Testing
@testable import Cicada

/// Deepgram's live messages (developers.deepgram.com: Results, UtteranceEnd, Error) turned into
/// the drafts and finished lines listening expects: one finished line per utterance.
struct DeepgramTests {
    private func results(_ text: String, start: Double, duration: Double, final: Bool, speechFinal: Bool = false,
                         fromFinalize: Bool = false, confidence: Double = 0.9, languages: [String]? = nil) -> Data {
        var alt: [String: Any] = ["transcript": text, "confidence": confidence]
        if let languages { alt["languages"] = languages }
        let msg: [String: Any] = ["type": "Results", "start": start, "duration": duration, "is_final": final,
                                  "speech_final": speechFinal, "from_finalize": fromFinalize,
                                  "channel": ["alternatives": [alt]]]
        return try! JSONSerialization.data(withJSONObject: msg)
    }

    @Test func urlAsksForTheLanguageAndNeverCarriesTheKey() {
        let ko = Deepgram.url(language: "ko").absoluteString
        #expect(ko.hasPrefix("wss://api.eu.deepgram.com/v1/listen?"))
        #expect(ko.contains("model=nova-3") && ko.contains("language=ko") && ko.contains("encoding=linear16")
                && ko.contains("sample_rate=16000") && ko.contains("interim_results=true") && ko.contains("utterance_end_ms="))
        #expect(Deepgram.url(language: "zh-CN").absoluteString.contains("language=zh-CN"))
        #expect(Deepgram.url(language: nil).absoluteString.contains("language=multi"))
        #expect(!ko.lowercased().contains("token") && !ko.lowercased().contains("key"))
    }

    @Test func draftsGrowUntilTheUtteranceEnds() throws {
        var a = DeepgramAssembler(spaced: true)
        let d1 = try a.take(results("Tell me", start: 6, duration: 1, final: false))
        #expect(d1.count == 1 && d1[0].text == "Tell me" && !d1[0].isFinal)
        let d2 = try a.take(results("Tell me more", start: 6, duration: 1.5, final: true))
        #expect(d2.count == 1 && d2[0].text == "Tell me more" && !d2[0].isFinal)
        let d3 = try a.take(results("about this", start: 7.5, duration: 0.5, final: false))
        #expect(d3.map(\.text) == ["Tell me more about this"] && !d3[0].isFinal)
        let done = try a.take(results("about this.", start: 7.5, duration: 0.6, final: true, speechFinal: true))
        #expect(done.count == 1)
        let line = done[0]
        #expect(line.isFinal && line.text == "Tell me more about this.")
        #expect(line.start == 6 && abs(line.end - 8.1) < 0.0001)
        // The next utterance starts afresh.
        let next = try a.take(results("Next", start: 9, duration: 0.3, final: false))
        #expect(next.map(\.text) == ["Next"])
    }

    /// An empty final can still be the one that ends the line (speech_final after the words came).
    @Test func emptyFinalStillEndsTheLine() throws {
        var a = DeepgramAssembler(spaced: true)
        _ = try a.take(results("Hello there", start: 0, duration: 1, final: true))
        let done = try a.take(results("", start: 1, duration: 0.4, final: true, speechFinal: true))
        #expect(done.map(\.text) == ["Hello there"] && done[0].isFinal)
        #expect(try a.take(results("", start: 2, duration: 0.4, final: true, speechFinal: true)).isEmpty)
    }

    @Test func utteranceEndAndFinalizeFlush() throws {
        var a = DeepgramAssembler(spaced: true)
        _ = try a.take(results("Привет", start: 0, duration: 0.8, final: true))
        let ended = try a.take(Data(#"{"type":"UtteranceEnd","channel":[0,1],"last_word_end":0.8}"#.utf8))
        #expect(ended.map(\.text) == ["Привет"] && ended[0].isFinal)
        _ = try a.take(results("как дела", start: 1, duration: 0.8, final: false))
        let forced = try a.take(results("как дела?", start: 1, duration: 0.9, final: true, fromFinalize: true))
        #expect(forced.map(\.text) == ["как дела?"] && forced[0].isFinal)
        // Words heard but not yet final when the stream ends are kept.
        _ = try a.take(results("до свидания", start: 3, duration: 0.5, final: false))
        let last = a.flush()
        #expect(last?.text == "до свидания" && last?.isFinal == true)
        #expect(a.flush() == nil)
    }

    @Test func cjkJoinsWithoutSpaces() throws {
        var a = DeepgramAssembler(spaced: false)
        _ = try a.take(results("今天", start: 0, duration: 0.5, final: true))
        let done = try a.take(results("开会。", start: 0.5, duration: 0.5, final: true, speechFinal: true))
        #expect(done.map(\.text) == ["今天开会。"])
    }

    @Test func reportsTheLanguageItHeard() throws {
        var a = DeepgramAssembler(spaced: true)
        let done = try a.take(results("Hola", start: 0, duration: 0.5, final: true, speechFinal: true, languages: ["es"]))
        #expect(done.first?.language == "es")
    }

    /// A line nobody ends (a long talk with no pause) is cut so it doesn't grow without bound.
    @Test func longLineIsCut() throws {
        var a = DeepgramAssembler(spaced: true)
        var out: [Recognition.Piece] = []
        for i in 0..<30 { out += try a.take(results("word\(i)", start: Double(i), duration: 1, final: true)) }
        #expect(out.contains { $0.isFinal })
    }

    @Test func errorMessageThrows() {
        var a = DeepgramAssembler(spaced: true)
        #expect(throws: Deepgram.Failure.self) {
            try a.take(Data(#"{"type":"Error","description":"bad","message":"x"}"#.utf8))
        }
        #expect((try? a.take(Data(#"{"type":"Metadata","duration":1}"#.utf8)))?.isEmpty == true)
    }
}
