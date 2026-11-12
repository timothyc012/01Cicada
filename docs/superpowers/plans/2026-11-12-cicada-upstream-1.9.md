# Cicada 1.9.0 integration

The user requested the current upstream update while retaining the local dictation, shortcut, Gemma and microphone changes. The verified GitHub release is v1.9.0, published 2026-11-12, whose commit is f119ba6.

## Preservation

Local changes were first checkpointed through 7e68037 on `feature/dictation-paste`. That branch remains available. A new `feature/dictation-paste-v1.9.0` branch merged the released tag with an explicit merge commit (1b01c4a), preserving both histories.

Conflicts were limited to additive localization blocks and website changelog items. Both sets of localization keys and all three local changelog items were retained alongside upstream release notes. The model code, microphone defaults, settings, shortcuts and dictation UI auto-merged and were inspected explicitly.

Retained: DictationEngine and paste policy, requested user Cmd+Ctrl+D setting, model/language/shortcut UI, keyless custom Gemma request override, Google bypass preference, idle-on-launch preference, ordinary room microphone defaults and rehearsal microphone exclusion.

Upstream adds independent notes providers/models, hands-free interpreting (opt-in), folder Markdown export, record playback improvements, and speech/import/stability fixes. The continuous room microphone remains on the ordinary capture path to coexist with other recording apps.

## Validation

- Full Swift suite: 351 tests in 52 suites passed.
- Localization: 1347 Korean keys, 0 missing, 0 TODO, 0 bad format specifiers; English/Japanese checks also passed. Existing unused keys remain.
- All conflict markers removed and git diff --check passed.
- Build and ad-hoc signature verification passed. App metadata reports 1.9.0 and the merged branch/commit.
- User preference Cmd+Ctrl+D remains stored as 2:4352; company Gemma endpoint and SSH tunnel remain configured outside the repository.

No official installer was copied over the local code and no release or push was made. AWhisper's separate model-label synchronization issue and performance comparison are being tracked separately; this update does not establish ASR accuracy or benchmark parity.

Runtime application was restarted only after listen/notes/speak were idle. Actual native settings UI now shows version 1.9.0, Dictation in Korean with Cmd+Ctrl+D, keyless localhost Gemma4:31b (0.3s translation check), on-device recognition and system speech, with Google bypass enabled. No OS privacy grants were made. Existing meeting records remained visible.
