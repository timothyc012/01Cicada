# Dictation Implementation Plan

**Goal:** Add Mac work dictation and automatic paste in the cloned Cicada.
**Spec:** `docs/superpowers/specs/2026-11-11-dictation.md`
**Architecture:** UI-free DictationEngine uses existing RecognitionStream and AudioSource; a dedicated paste helper enforces target/clipboard policy. AppModel wires a third hotkey and existing settings/menu surfaces.

- [x] Establish baseline tests/build. Resolve local toolchain setup without changing unrelated product behavior.
- [x] Write failing tests for transcript replacement and focus/clipboard policy. Implement dictation engine, lifecycle cancellation and paste helper.
- [x] Wire language/shortcut settings, panel controls and file-based debug commands; localize Chinese/en/ja/ko and update the four READMEs and site changelog.
- [x] Run suites and build; exercise real file recognition and a real editable target. Obtain fresh final read-only review and fix significant findings. Record evidence and limitations.

## Verification

- Baseline: 313 tests in 48 suites passed. Final suite: 320 tests in 49 suites passed, including real engine cancel → restart → old finish suppression, interpreting rehearsal exclusion, and clipboard retention for delayed paste.
- Chinese/English/Japanese/Korean localization check: 0 missing, 0 TODO, 0 bad format specifiers. Existing unused keys remain.
- Real Korean synthetic audio (`say -v Yuna` recording) passed through DictationEngine and the actual native RecognitionStream. Result included all three sentences, beginning 안녕하세요 and ending 테스트하고 있습니다. Clipboard contents were asserted directly. Cancelling a second run left the prior result intact and the engine idle.
- The development app reported Accessibility=false. Its copy-only fallback was verified; actual Cmd+V into an external field and physical microphone input remain manual checks after the user grants the macOS permissions. Permissions were not granted automatically.
- UI reviewed through the app's native panel/window render commands. Computer-use window discovery was unavailable. Offscreen ImageRenderer cannot render native Picker/Toggle controls; those artifacts are not evidence of broken runtime controls. Fixed explicit dark-on-light text in the new panel.
- Independent read-only review identified delayed clipboard restoration and rehearsal microphone admission issues; both fixed. Final text stays on the clipboard; microphone admission is now checked by SpeakEngine and SpeakTester.

## Decisions and limitations

- Open idle by default with an explicit listen-on-launch setting: dictation must not depend on the meeting system-audio tap. Original automatic capture hung in Core Audio on this machine; no unrelated audio-tap rewrite was attempted.
- Keep dictated text on the clipboard after paste. A queued Cmd+V does not prove a target has read it, so restoring unrelated prior contents on a timer is unsafe.
- Dictation is original-language recognition with system punctuation; no new LLM rewriting step or TTS is added. Existing cloud recognition configuration applies; fixed language is passed explicitly.
- This change is Mac-only and retains Cicada's existing language choices; it does not add Russian support or a Windows dictation port.
- Local toolchain workaround: the CLT upgrade left 2023 private PackageDescription interfaces next to Swift 6.3 public interfaces. A temporary VFS overlay maps the stale private interfaces to the public ones, with a fresh module cache (`/tmp/cicada-toolchain/bin/swift` wrapper). The repository manifest is unchanged; no system toolchain files were removed. Builds and tests used that local wrapper.

## Usage

Open `build/Cicada.app`. In Settings → Dictation choose the language and shortcut (default Ctrl+Option+D). Allow Accessibility for automatic paste, then focus an external text field and press the shortcut to start/stop. If the original field cannot be confirmed, the result stays on the clipboard. Allow microphone access on the first real recording. The original onboarding is for meeting/system-audio features; dictation settings can be opened independently.

Final `scripts/build.sh` completed successfully and the development app passed `codesign --verify --deep --strict`. No release, push or installation over another app was performed.
