# Cicada Glossy Dictation HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Show visible live dictation status without taking focus from the destination field.

**Architecture:** A dedicated native nonactivating panel reads typed dictation outcomes and real per-run audio levels. AppModel forwards engine changes; a bounded controller clock updates recording time and meters and guards completion dismissals.

**Tech Stack:** AppKit, SwiftUI, NSGlassEffectView on macOS 26 or NSVisualEffectView fallback, Swift Testing.

**Spec:** `../specs/2026-11-12-glossy-status-design.md`

## Global Constraints

- Use the approved top-center Glossy surface; keep native panels nonactivating.
- Preserve keyboard bindings, recognition routes and clipboard/focus safety.
- No fake audio and no unrelated engine changes.

## Review Focus

- A completion timer firing after a new recording starts must be ignored.
- Missing audio or a backend error must not display insertion success.
- Long localized text must fit without clipping or hiding the input-level meter.
- Showing a HUD must leave the original text field and frontmost app unchanged.
- Active recording and unsaved user work must survive deployment preparation.

### Task 1: Native status surface and lifecycle

**Files:** Create `Sources/Cicada/DictationHUD.swift`, `Tests/CicadaTests/DictationHUDTests.swift`; modify `DictationEngine.swift`, `AppModel.swift`, localization resources, README variants and `site/changelog.json`.

**Interfaces:** Controller `DictationHUDController.update(engine: DictationEngine, shortcut: Shortcut)`; structured engine completion outcome and real latest RMS; pure status/dismissal policy for tests. Developer-only snapshot/render controls may inspect the real panel, never capture audio or paste text.

- [x] Write failing lifecycle tests: recording -> processing -> inserted/copied/error; launch idle hidden; cancelled/stale dismissal cannot hide the next run; silence detection uses actual zero/missing audio.
- [x] Implement typed engine outcome, real level access and native glass panel. Keep status callbacks on MainActor and timer work bounded to visible state.
- [x] Run the full unit suite with the existing temporary CLT manifest overlay. Run localization checks; do not edit system files or Package.swift.
- [x] Render real native views in light/dark and Korean/English; verify long copy, panel canBecomeKey=false and click-through.
- [x] Review, commit, build a signed bundle, and let the root agent deploy only after capture checks.

## Verification and local deployment (2026-11-12)

- Feature commit `4d62b2f`:369 unit tests passed;1,364 localization keys in English/Japanese/Korean with zero missing/TODO/format errors; fresh read-only review clean.
- Native English/Korean × light/dark state matrix passed16 cases for actual material, label fit and nonactivating properties. Evidence remains local at `/tmp/cicada-hud-qa/`; PNGs contain native content/highlights, while WindowServer composites the live glass backdrop.
- Installed tested debug binary at `build/Cicada.app` and signed with the existing fixed designated requirement `identifier "com.wquguru.cicada.dev"`. Old app preserved at `build/Cicada-before-glossy-hud.app`.
- Initial staged bundle reused old localized resources; live preview caught the new Chinese fallback text. Corrected by copying current Localizable.strings for en/ja/ko/zh-Hans plus zh-Hant fallback, preserving the existing dev InfoPlist strings; resigned/relaunched. All installed localization files now match source.
- Final installed no-audio preview: title `듣는 중`, hint `⌃ ⌘ D를 다시 누르면 완료`,368×66,NSGlassEffectView.clear, visible=true, key/main/canBecomeKey/Main=false, labelsFit=true. Focus diagnostics before/after are identical. Preview then switched off; dictation phase stayed idle and Accessibility stayed true. Shortcut registered with status0; user shortcut/settings/paste safeguards unchanged.
- Both meeting capture and speaking were idle before replacement. No real microphone input, clipboard delivery or physical global-hotkey test was performed during this update. macOS14 material fallback compiled, but runtime testing used macOS26.
