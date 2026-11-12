# Company Gemma setup

The user authorized restoring the existing company SSH connection and configuring Cicada translation and meeting notes. The server already accepts OpenAI-compatible requests without an API key through its loopback Ollama endpoint. SSH provides authentication and transport; no dummy API key is created.

## Changes

- A local-only SSH forward on `127.0.0.1:11434` connects to the authorized server's loopback port. A user LaunchAgent (`com.awhisper.hderc-ollama-tunnel`) reconnects it after connection failure and at login. The server's bind address, authentication, and models were not changed.
- Cicada Dev uses the custom provider, `http://localhost:11434/v1`, and `gemma4:31b`. Original on-device recognition is retained. `aiCustomOnly` bypasses Google translation.
- Local Gemma 4 requests use Ollama's `reasoning_effort: none`. Other custom models/remote endpoints retain their existing template options. A keyless connected onboarding screen no longer shows a fabricated-looking masked-key placeholder.

## Verification

- Before the fix, the existing Cicada request options left Gemma thinking: an 180-token translation request ended with `length`, no answer and 521 reasoning characters. With thinking disabled the same warm translation completed in 0.3 s.
- Regression tests first failed (10 assertions), then the full suite passed: 323 tests in 49 suites. Tests cover Gemma 4 31B/e4B/base tags on IPv4/IPv6/localhost, unchanged other-provider behavior, and actual LingClient calls without a stored custom API key.
- The native app's service check passed without a key: reach, keyless access, translation, and JSON output. Initial onboarding was completed through the actual UI. No new OS permissions were granted and the optional virtual-microphone installer was skipped.
- A synthetic four-line session passed through the actual ListenEngine → TranslationService → LingClient → company Gemma → NotesEngine pipeline, without audio capture. All four translations were persisted; notes covered all four lines with a topic, conclusion, glossary and to-do. This verifies a short functional path, not long-meeting accuracy.
- The pre-existing AWhisper `localhost:11434/v1` endpoint reaches the server again as well.

## Local artifacts

The user LaunchAgent lives under `~/Library/LaunchAgents/com.awhisper.hderc-ollama-tunnel.plist`; its log is `~/Library/Logs/hderc-ollama-tunnel.log`. The existing SSH host alias is referenced by that local configuration, not embedded in product code. Company server host details and credentials are not committed.

Native builds/tests use the temporary local CLT compatibility wrapper documented in the dictation plan. The app is `build/Cicada.app` (development bundle). No release or remote push is part of this setup.
