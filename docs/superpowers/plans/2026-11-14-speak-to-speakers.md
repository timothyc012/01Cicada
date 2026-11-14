# Read interpreting out of the speakers

The user mostly talks face to face through the MacBook microphone and wants the other person to hear the translation. Interpreting only ever sent the voice to a virtual mic (`SpeakEngine.outputDevice`), and on macOS 26 the mic button gives `listenSource == "both"`, so there is no reliable automatic signal for "nobody online". A heuristic such as "something reads BlackHole" was rejected: AWhisper and Cicada's own system-mic switch both touch the default input.

Added one explicit switch, Settings › Interpreting › 从扬声器读出来 (`speakToSpeakers`, default off). Off keeps every previous path unchanged.

On:
- `SpeakEngine.output(toSpeakers:…)` returns the system output; the virtual-mic checks in `pressBegan` and before speaking use speaker wording instead.
- A press while the translation is still playing is refused (the press mic would record it).
- `AppModel.roomMuted` keeps the room mic muted during `.speaking` as well as `.listening`; the system-audio tap already excludes Cicada's own process.
- `wantsSystemMic` is false, so the system mic is not switched to BlackHole.
- `keepUnit` is false: with the system mic left real, a VoiceProcessingIO unit kept ready while listening would starve other apps' input (`VoiceMic`, issue #24). The unit is made per press instead, so each press's first words wait ~1–1.7 s, and other apps' input still dips during a press.
- Hands-free is paused (no meeting to tell its own echo from).
- The settings page hides the virtual-mic setup/health card, 试一句 (it records the virtual mic), the system-mic auto-switch row and the 译文送到 row; panel hints reuse the existing 扬声器 strings.

Tests: `SpeakOutputTests` covers routing on/off (including a stored speaker choice and no virtual mic) and room muting per phase. Full suite 378 pass. The local CLT needed the documented PackageDescription VFS overlay for `scripts/test.sh` and `scripts/strings.py` (0 missing keys in en/ja/ko).

Not yet verified: a real press with spoken output through the speakers, the English settings UI, and whether the room mic's echo gate plus this mute fully keeps the spoken translation out of the record. These need the rebuilt app installed with the user's approval.
