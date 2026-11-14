import Testing
@testable import Cicada

/// Russian: no speech model on this Mac, so a picked Russian is heard by your own speech service.
struct RussianTests {
    @Test func russianCanBeHeardAndSpoken() {
        #expect(sourceLanguages.contains { $0.locale == "ru-RU" && $0.code == "ru" })
        #expect(targetLanguages.contains { $0.code == "ru" })
        #expect(Recognition.needsServer("ru-RU"))
        #expect(!Recognition.needsServer("ko-KR"))
    }

    @Test func onlyAPickedLanguageWithoutAModelGoesToTheServer() {
        #expect(ListenEngine.serverHears(preferred: false, fixedLocale: "ru-RU"))
        #expect(!ListenEngine.serverHears(preferred: false, fixedLocale: "de-DE"))
        #expect(!ListenEngine.serverHears(preferred: false, fixedLocale: nil))
        #expect(ListenEngine.serverHears(preferred: true, fixedLocale: nil))
    }

    @Test func aWhisperLineWithoutALanguageIsRussianWhenCyrillic() {
        let heard = CloudHearing.transcript("Здравствуйте, меня зовут Анна.", reported: nil, hint: nil, target: "ko", seconds: 3)
        #expect(heard?.lang == "ru")
        let reported = CloudHearing.transcript("Здравствуйте", reported: "russian", hint: nil, target: "ko", seconds: 2)
        #expect(reported?.lang == "ru")
    }
}
