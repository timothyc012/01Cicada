# Dictation hotkey diagnosis

The user reported that Cmd+Ctrl+D failed and changing the combination also failed. The current user-selected setting is Ctrl+Option+D (`2:6144`); preserve it during diagnosis.

Added read-only developer diagnostics: Carbon handler/registration status, whether shortcuts are suspended, received dictation press count, and per-run audio buffer/frame/peak counters. No dictated content is added to logs. `dictateState` exposes these fields alongside its existing state; `shortcuts` logs the same metrics.

Installed a diagnostic dev bundle at the existing `build/Cicada.app` path with the same bundle identifier and designated requirement. Previous bundle is retained as `build/Cicada-before-shortcut-diagnostics.app`. Before replacing it, meeting, speaking, and dictation were idle. Fresh state reports registration success (`0`), handler success (`0`), registered=true, suspended=false. Accessibility is false, affecting auto-paste separately. System Secure Input is false.

Three in-process Carbon event tests prove that handlers route matching IDs, ignore other IDs, and remain usable across complete press/release cycles. These do not prove physical keyboard delivery. Full suite: 354 tests pass (`/tmp/cicada-shortcut-diagnostics-tests.log`).

The local CLT install has mismatched public/private PackageDescription interfaces (Swift 6.3.3 versus stale 5.9.2). Tests were run with a scoped temporary VFS overlay, without modifying Package.swift or system files:

`scripts/test.sh --manifest-cache none -Xbuild-tools-swiftc -vfsoverlay -Xbuild-tools-swiftc /tmp/cicada-hotkey-repro/manifest-overlay.json -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc /tmp/cicada-hotkey-repro/manifest-cache`

Pending: one physical press of the current Ctrl+Option+D combination. A 40-second observation saw no press events, but the user has not yet confirmed performing that test. Do not conclude a root cause or claim a fix until that observation is available. Cicada Accessibility approval is also still pending; do not grant it based on approval to update AWhisper.
