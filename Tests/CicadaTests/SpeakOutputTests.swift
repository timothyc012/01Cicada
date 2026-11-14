import Testing
@testable import Cicada

/// 从扬声器读出来: off keeps translations out of the speakers; on reads them in the room.
struct SpeakOutputTests {
    private let speakers = OutputDevice(id: 1, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers")
    private let blackHole = OutputDevice(id: 2, uid: "BlackHole2ch_UID", name: "BlackHole 2ch")
    private let loopback = OutputDevice(id: 3, uid: "Loopback_UID", name: "Loopback Audio")

    @Test func offSendsOnlyToAVirtualMic() {
        let all = [speakers, blackHole]
        #expect(SpeakEngine.output(toSpeakers: false, stored: "", all: all, systemOutput: speakers) == blackHole)
        // A stored speaker choice from before never reaches the room.
        #expect(SpeakEngine.output(toSpeakers: false, stored: speakers.uid, all: all, systemOutput: speakers) == blackHole)
        #expect(SpeakEngine.output(toSpeakers: false, stored: loopback.uid, all: all + [loopback], systemOutput: speakers) == loopback)
    }

    @Test func offWithoutAVirtualMicSendsNothing() {
        #expect(SpeakEngine.output(toSpeakers: false, stored: "", all: [speakers], systemOutput: speakers) == nil)
    }

    @Test func onReadsOutOfTheSystemOutputWithoutAVirtualMic() {
        #expect(SpeakEngine.output(toSpeakers: true, stored: blackHole.uid, all: [speakers, blackHole], systemOutput: speakers) == speakers)
        #expect(SpeakEngine.output(toSpeakers: true, stored: "", all: [speakers], systemOutput: speakers) == speakers)
        #expect(SpeakEngine.output(toSpeakers: true, stored: "", all: [speakers], systemOutput: nil) == nil)
    }

    @Test func roomMicStaysMutedWhileTheSpeakersReadTheTranslation() {
        #expect(AppModel.roomMuted(phase: .listening, toSpeakers: false))
        #expect(!AppModel.roomMuted(phase: .speaking, toSpeakers: false))
        #expect(AppModel.roomMuted(phase: .listening, toSpeakers: true))
        #expect(AppModel.roomMuted(phase: .speaking, toSpeakers: true))
        #expect(!AppModel.roomMuted(phase: .translating, toSpeakers: true))
        #expect(!AppModel.roomMuted(phase: .idle, toSpeakers: true))
    }
}
