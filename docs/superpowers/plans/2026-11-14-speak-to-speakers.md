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

Native check (dev build `d1c3aac`, debug command `speakToSpeakers:on|off`): turning it on restored the system mic from BlackHole to the MacBook mic; `state:speak` showed output MacBook Pro speakers, keepUnit false, hands-free false. A Korean `say` clip through `speakFile` was translated and logged `spoke 318 buffers to MacBook Pro 스피커`, with `room mic muted` from the start of speaking until 0.4 s after. Settings renders in Korean and English show the new row and hide the virtual-mic card and rows; off renders as before.

Not yet verified: a physical right-⌥ press, and a real meeting with the room mic listening (whether any echo of the spoken translation reaches the record). During the check the user's dev preferences were found moved to the Trash at 21:32 (not by this change); they were restored with `defaults import`, and the company Gemma check passed (`reach=ok text=ok`).
