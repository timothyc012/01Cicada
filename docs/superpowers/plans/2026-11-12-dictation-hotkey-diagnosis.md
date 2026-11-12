# Dictation hotkey diagnosis

The user reported that Cmd+Ctrl+D failed and changing the combination also failed. During initial diagnosis the setting was Ctrl+Option+D (`2:6144`). The user subsequently requested restoring Control+Command+D: restored `2:4352` while the app was stopped, relaunched, and verified both the native settings UI and `dictateState` show ⌃ ⌘ D with registered=true, handlerStatus=0, registrationStatus=0, and shortcutsSuspended=false.

Added read-only developer diagnostics: Carbon handler/registration status, whether shortcuts are suspended, received dictation press count, and per-run audio buffer/frame/peak counters. No dictated content is added to logs. `dictateState` exposes these fields alongside its existing state; `shortcuts` logs the same metrics.

Installed a diagnostic dev bundle at the existing `build/Cicada.app` path with the same bundle identifier and designated requirement. Previous bundle is retained as `build/Cicada-before-shortcut-diagnostics.app`. Before replacing it, meeting, speaking, and dictation were idle. Fresh state reports registration success (`0`), handler success (`0`), registered=true, suspended=false. Accessibility is false, affecting auto-paste separately. System Secure Input is false.

Three in-process Carbon event tests prove that handlers route matching IDs, ignore other IDs, and remain usable across complete press/release cycles. These do not prove physical keyboard delivery. Full suite: 354 tests pass (`/tmp/cicada-shortcut-diagnostics-tests.log`).

The local CLT install has mismatched public/private PackageDescription interfaces (Swift 6.3.3 versus stale 5.9.2). Tests were run with a scoped temporary VFS overlay, without modifying Package.swift or system files:

`scripts/test.sh --manifest-cache none -Xbuild-tools-swiftc -vfsoverlay -Xbuild-tools-swiftc /tmp/cicada-hotkey-repro/manifest-overlay.json -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc /tmp/cicada-hotkey-repro/manifest-cache`

Initial observation: an earlier 40-second check of Ctrl+Option+D saw no press events, but the user had not confirmed performing that test. Physical presses were subsequently observed with the restored Control+Command+D combination (below). Cicada Accessibility approval is still pending; do not grant it based on approval to update AWhisper.

## Physical input evidence and held-key fix

After the user tried the restored shortcut, diagnostics recorded 14 actual presses. The key is reaching Cicada. Several arrived while the previous action was preparing or had just stopped, repeatedly cancelling/restarting the run. The microphone supplied nonzero audio (one run: 95 buffers, 456,000 captured frames, 151,796 submitted frames, peak 0.0437); a short run produced two recognized characters. Accessibility remains false, independently preventing automatic insertion.

A native Carbon regression confirmed repeated pressed events were forwarded repeatedly, and unmatched/duplicate releases also invoked callbacks. Added held-state filtering: only the first down is delivered until its release; only a matching release is delivered; unregister resets the state. Separate complete presses still work. RED: `/tmp/cicada-hotkey-repeat-red.log`. Full GREEN: 355 tests pass (`/tmp/cicada-hotkey-repeat-green.log`). The fix prevents duplicate events from disrupting dictation; it does not establish the cause of every empty transcription. Auto-paste permission is still awaiting explicit user approval.

Installed the tested held-key fix at `build/Cicada.app` after confirming dictation idle and quitting natively. Backup: `build/Cicada-before-held-key-fix.app`. Signature verification passed with the same bundle ID/designated requirement; the installed executable matches the tested binary. Relaunched with Control+Command+D still registered successfully. Native physical validation of the deduplicated behavior and automatic paste remain pending.

## Orca delivery result

The user enabled Accessibility manually; the running Cicada reports `accessibility=true`. In a subsequent run the restored hotkey arrived five times, microphone audio reached recognition, and eight characters were finalized. Added policy-preserving block-reason diagnostics, captured/current application and role metadata, plus read-only `dictationTarget` probing. Full suite: 361 tests pass, including 36 combinations proving `blockReason` preserves the existing paste policy. Installed this diagnostic build at the same path (backup `build/Cicada-before-paste-target-diagnostics.app`).

The user confirmed the destination was the Orca composer. Actual delivery report: same process/application (`com.stablyai.orca`), target role `AXTextArea`, current role `AXWebArea`, `sameField=false`, reason `focused_field_changed`. Thus the completed run copied its transcript rather than inserting into an unfocused/different element. No safety check was relaxed. The next run also reached recording while key-held and physical-key-down flags were both false, excluding a latched held-key guard in that observation. The user noted that recording may have been working without visible feedback; dictation currently updates a small menu-bar indicator and its menu panel, without a floating dictation HUD.

Electron's documented `AXManualAccessibility` API was probed through the dev command and returned success, but the Orca text area was already captured before enabling it; this is not established as the cause. Reference: https://www.electronjs.org/docs/latest/tutorial/accessibility . No transcript content was logged by the new delivery diagnostics.
