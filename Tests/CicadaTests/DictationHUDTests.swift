import Foundation
import Testing
@testable import Cicada

@Suite struct DictationHUDTests {
    @Test func idleLaunchStaysHidden() {
        var state = DictationHUDState()
        state.update(phase: .idle, runID: 0, outcome: nil, now: 0)
        #expect(state.status == .hidden)
        #expect(state.dismissal == nil)
    }

    @Test func recordingFinishingAndInsertedHaveDistinctStates() {
        var state = DictationHUDState()
        state.update(phase: .preparing, runID: 1, outcome: nil, now: 0)
        #expect(state.status == .preparing)
        state.update(phase: .recording, runID: 1, outcome: nil, now: 1)
        #expect(state.status == .recording)
        #expect(state.elapsed(at: 13) == 12)
        state.update(phase: .finishing, runID: 1, outcome: nil, now: 13)
        #expect(state.status == .finishing)
        state.update(phase: .idle, runID: 1, outcome: .inserted, now: 14)
        #expect(state.status == .result(.inserted))
        #expect(state.dismissal?.deadline == 16)
    }

    @Test func copiedErrorsAndSilenceRemainVisibleForFourSeconds() {
        for outcome: DictationOutcome in [.copied(reason: "application_changed"), .failed("offline"), .noAudio, .noSpeech] {
            var state = DictationHUDState()
            state.update(phase: .idle, runID: 1, outcome: outcome, now: 8)
            #expect(state.status == .result(outcome))
            #expect(state.dismissal?.deadline == 12)
            state.update(phase: .idle, runID: 1, outcome: outcome, now: 10)
            #expect(state.dismissal?.deadline == 12)
        }
    }

    @Test func oldDismissalCannotHideNewRecordingOrNotice() {
        var state = DictationHUDState()
        state.update(phase: .idle, runID: 1, outcome: .inserted, now: 0)
        let old = state.dismissal!
        state.update(phase: .preparing, runID: 2, outcome: nil, now: 1)
        state.dismiss(old, now: 3)
        #expect(state.status == .preparing)
        state.update(phase: .idle, runID: 2, outcome: .failed("offline"), now: 4)
        state.dismiss(old, now: 8)
        #expect(state.status == .result(.failed("offline")))
        let current = state.dismissal!
        state.dismiss(current, now: 7)
        #expect(state.status != .hidden)
        state.dismiss(current, now: 8)
        #expect(state.status == .hidden)
        state.update(phase: .idle, runID: 2, outcome: .failed("offline"), now: 9)
        #expect(state.status == .hidden)
    }

    @Test func cancellationExpiresAndDoesNotHideNewRun() {
        var state = DictationHUDState()
        state.update(phase: .idle, runID: 1, outcome: .cancelled, now: 0)
        #expect(state.dismissal?.deadline == 2)
        let old = state.dismissal!
        state.update(phase: .recording, runID: 2, outcome: nil, now: 1)
        state.dismiss(old, now: 3)
        #expect(state.status == .recording)
    }

    @Test func stalledInputClearsMeterAndRecentSignal() {
        var audio = DictationAudioHistory()
        #expect(audio.levels(at: 0).isEmpty)
        #expect(!audio.hasRecentAudio(at: 0))
        audio.receive(DictationAudioLevel(samples: [0.3, -0.3]), at: 1)
        #expect(!audio.levels(at: 1.3).isEmpty)
        #expect(audio.levels(at: 1.5).isEmpty)
        #expect(audio.hasRecentAudio(at: 3.9))
        #expect(!audio.hasRecentAudio(at: 4.1))
        audio.receive(.empty, at: 5)
        #expect(audio.levels(at: 5).allSatisfy { $0 == 0 })
        #expect(!audio.hasRecentAudio(at: 5))
        audio.receive(DictationAudioLevel(samples: [0.2]), at: 6)
        #expect(audio.hasRecentAudio(at: 6))
    }

    @Test func silenceAndMeterAreDrivenByCapturedAudio() {
        #expect(DictationAudioLevel.empty.isSilent)
        #expect(DictationAudioLevel(samples: [0, 0, 0]).isSilent)
        let voice = DictationAudioLevel(samples: [0.2, 0.4, -0.2, 0])
        #expect(!voice.isSilent)
        #expect(voice.rms > 0.24 && voice.rms < 0.25)
        #expect(voice.peak == 0.4)
        #expect(voice.normalized > 0)
        #expect(DictationAudioLevel.empty.normalized == 0)
    }
}

extension DictationHUDTests {
    @MainActor @Test func preparationFailurePublishesTypedErrorAtomically() async throws {
        let engine = DictationEngine { _ in throw DictationEngine.problem("test recognition unavailable") }
        var notices: [DictationOutcome] = []
        engine.onChange = { if let outcome = engine.outcome { notices.append(outcome) } }
        // An explicit file bypasses the microphone permission path; recognition fails before opening it.
        engine.start(locale: "en-US", device: nil, file: URL(fileURLWithPath: "/unused-synthetic-test.wav"))
        for _ in 0..<100 {
            if !engine.busy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.phase == .idle)
        #expect(engine.outcome == .failed("test recognition unavailable"))
        #expect(notices == [.failed("test recognition unavailable")])
        #expect(engine.message == "test recognition unavailable")
    }
}
