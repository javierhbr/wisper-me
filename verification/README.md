# Verification

Verified on Apple Silicon, macOS 26.6.2, Swift 6.3.2.

## Completed

- Automatic clipboard copy after transcription was verified in the packaged app. Command–V pasted the completed transcript without clicking Copy, including after the former clipboard-restoration delay.

- Native debug compilation and release app packaging.
- Ad hoc code-signature verification.
- Swift unit tests for formatting, spoken punctuation, paragraphs, bullets, endpoint restrictions, polishing requests, and preservation of text when polishing returns empty output.
- Runtime-installer cancellation terminates and reaps its owned child.
- Python worker protocol: valid JSON-line framing, progress events, rejected unsupported engines, missing loaded model, and clean shutdown.
- Real Whisper Tiny inference on generated speech. Word error rate for this one short sample: 13.33%.
- Real Parakeet 0.6B v3 inference on the same generated passage. Word error rate for that sample: 0%.
- Both speech models were loaded through the packaged app's UI.
- Native audio-file import produced actual transcripts for both engines, including a model switch in the same worker.
- Installed-model discovery against the local Ollama service.
- Real local text polishing through wisprM's client with Qwen 2.5 1.5B. The test preserved the speaker and recipient.
- The native app's Parakeet → local Qwen → text pipeline completed without an error.
- Dictate, Models, Settings, History, and the standard Mac menu were inspected through the accessibility tree. The model screen was visually inspected.

The single synthetic passage is a functional check, not an accuracy or latency benchmark. The JSON reports retain expected and actual speech output. First-run times include model download/loading and must not be presented as steady-state latency.

## Not yet verified

- Live microphone capture on this installation: the user has not granted microphone access for this new app.
- Actual insertion into a different application, secure-field exclusion at runtime, across real applications: Accessibility approval is pending.
- Broad compatibility with every Mac application or language.
- Launch-at-login behavior after logout/restart.
- Intel Macs, App Store distribution, Developer ID signing, or notarization.
- Arbitrary custom weights or arbitrary text servers. The app implements compatible interfaces, not universal model-format support.

Permission-dependent paths are implemented and compiled; they are not represented as completed end-to-end tests.

## Local-model observations

Whisper Tiny misrecognized “tomorrow morning” in the sample. Parakeet transcribed it exactly. Qwen 0.5B changed a sentence's meaning/structure during polishing; Qwen 1.5B passed the tested case. Polishing remains optional and the original dictation remains accessible.

The local MLX runtime and both speech models were installed/downloaded for these checks. Local Qwen 0.5B and 1.5B models were also downloaded into Ollama for comparison.
