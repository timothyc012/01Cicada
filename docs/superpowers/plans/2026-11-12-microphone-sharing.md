# Microphone sharing mitigation

AWhisper recorded zero or near-silent microphone input while Cicada's continuous room side held a VoiceProcessingIO unit. Cicada's own VoiceMic documentation describes cross-process input starvation from this unit even when bypassed. Runtime was switched to ordinary RoomMic capture and verified as room running, echoCancelled=false and voiceMic=false, with speech activity present.

Default room capture now uses the ordinary input path, retaining echo gating and transcript deduplication. The low-level processing path remains diagnostic opt-in. Existing 323 tests passed and a dev app build succeeded. This is a configuration change; no mirror test of the Boolean defaults was added.

The user retried AWhisper after the mitigation and still received empty transcription. Therefore this change is a microphone coexistence mitigation, not proof that the complete AWhisper fault has been resolved. Further AWhisper capture/worker diagnosis remains in progress.
