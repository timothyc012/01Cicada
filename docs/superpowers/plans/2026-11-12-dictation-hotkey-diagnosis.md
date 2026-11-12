# Dictation hotkey diagnosis

The user reported that Cmd+Ctrl+D failed and changing the combination also failed. During initial diagnosis the setting was Ctrl+Option+D (`2:6144`). The user subsequently requested restoring Control+Command+D: restored `2:4352` while the app was stopped, relaunched, and verified both the native settings UI and `dictateState` show ⌃ ⌘ D with registered=true, handlerStatus=0, registrationStatus=0, and shortcutsSuspended=false.

Added read-only developer diagnostics: Carbon handler/registration status, whether shortcuts are suspended, received dictation press count, and per-run audio buffer/frame/peak counters. No dictated content is added to logs. `dictateState` exposes these fields alongside its existing state; `shortcuts` logs the same metrics.

Installed a diagnostic dev bundle at the existing `build/Cicada.app` path with the same bundle identifier and designated requirement. Previous bundle is retained as `build/Cicada-before-shortcut-diagnostics.app`. Before replacing it, meeting, speaking, and dictation were idle. Fresh state reports registration success (`0`), handler success (`0`), registered=true, suspended=false. Accessibility is false, affecting auto-paste separately. System Secure Input is false.

Three in-process Carbon event tests prove that handlers route matching IDs, ignore other IDs, and remain usable across complete press/release cycles. These do not prove physical keyboard delivery. Full suite: 354 tests pass (`/tmp/cicada-shortcut-diagnostics-tests.log`).

The local CLT install has mismatched public/private PackageDescription interfaces (Swift 6.3.3 versus stale 5.9.2). Tests were run with a scoped temporary VFS overlay, without modifying Package.swift or system files:

`scripts/test.sh --manifest-cache none -Xbuild-tools-swiftc -vfsoverlay -Xbuild-tools-swiftc /tmp/cicada-hotkey-repro/manifest-overlay.json -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc /tmp/cicada-hotkey-repro/manifest-cache`

Pending: one physical press of the restored Control+Command+D combination. An earlier 40-second observation of Ctrl+Option+D saw no press events, but the user had not confirmed performing that test. Do not conclude a root cause or claim a fix until a physical press is observed. Cicada Accessibility approval is also still pending; do not grant it based on approval to update AWhisper.
