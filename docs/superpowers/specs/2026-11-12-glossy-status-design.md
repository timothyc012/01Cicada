# Glossy dictation status design

The user approved the transparent Glossy preview and explicitly requested applying it to both Cicada and AWhisper. Use a small top-center status surface below the menu bar. Keep current shortcuts, recognition, translation, clipboard policy and history behavior.

- Glass material: actual native background blur on macOS, translucent tint, subtle white highlight, soft shadow, about 22 pt corners; readable opaque labels and app accent (Cicada orange, AWhisper teal). No wallpaper or fake backdrop inside the shipped HUD.
- The status surface never becomes the key/main window or activates its app. Cicada is click-through; AWhisper retains its existing nonactivating cancel control.
- Real states: preparing, listening with elapsed time and real input levels, processing, inserted, copied-only, and error/no audio. No random or simulated audio meters.
- Copied-only explains why automatic insertion was skipped and shows a paste hint. Never call copied text inserted or report a failed output as success.
- Completion hides after about 2 seconds; copied/error notices stay about 4 seconds. Preserve AWhisper's existing 4-second expanded result-reading behavior. Older timers/events must not hide a newer recording.
- Keep text legible in light/dark and accessibility settings, including reduced motion and transparency/contrast fallback.
- Do not start/cancel a user recording to test or restart during active capture. Prepare signed bundles and preserve user settings/permissions.
