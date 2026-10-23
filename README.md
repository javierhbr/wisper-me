# wisprM

An original native macOS voice-to-text app using SwiftUI/AppKit and local MLX speech models. No Wispr Flow code, files, assets, protocols, or branding are included.

## Use the app

Open **dist/wisprM.app** (local version 0.1.1).

1. In **Models**, install the local runtime if needed.
2. Choose Whisper or Parakeet, then **Download & load model**.
3. Allow microphone access when you start dictation.
4. Enable Accessibility in **Settings** for direct insertion into supported text fields.
5. Focus a text field and press **Control–Option–Space**. Speak, then press it again to finish.

Every completed transcript is copied to the clipboard and remains available for **Command–V**, including when direct insertion is disabled or unavailable. Starting from wisprM's window writes to its scratchpad. **Import audio…** / Command–O processes a supported existing audio file without deleting the original.

Direct insertion is restricted to a verified, editable, unprotected Accessibility text element. There is no global keyboard/Paste synthesis. If the destination changes, cannot be verified, or rejects direct insertion, the transcript remains available on the clipboard for deliberate Paste.

## Speech models

| Engine | Initial model | Alternatives |
| --- | --- | --- |
| Whisper | mlx-community/whisper-tiny, 39M parameters | Tiny / Base / Small presets; compatible MLX weights |
| Parakeet | mlx-community/parakeet-tdt-0.6b-v3, 0.6B parameters | Compatible Parakeet MLX weights |

The corrected Base and Small repositories are mlx-community/whisper-base-mlx and mlx-community/whisper-small-mlx. Default model revisions are pinned in runtime/models.lock.json. Cached pinned weights load without a network request; a cache miss downloads the explicitly selected model. Custom remote model IDs can use an immutable revision: repo/name@<40-character-commit>. Absolute local model folders are also supported.

Whisper Tiny emphasizes speed and size. Parakeet 0.6B is larger. Model accuracy varies. Recognition runs after capture finishes; this build does not show partial streaming transcripts.

Requirements: **Apple Silicon**, **macOS 14+**, and an existing **Python 3.12 or 3.13** for first-time runtime setup. The runtime is already installed on this machine. The native app is small; the separately installed MLX/Python runtime and model weights occupy substantially more disk space.

## Formatting

Names, URLs, email addresses, paths, and backtick code spans retain their internal case and punctuation. Ordinary words such as “colon” are preserved.

**Interpret spoken punctuation commands in English** is off by default. Enable it in Settings to interpret phrases such as “new paragraph”, “comma”, or “question mark”. Select English when using these commands with Parakeet. Local cleanup also handles unambiguous English hesitations and spacing. Professional/casual rewriting is available through optional text polishing.

**Show original** lets you compare and copy the original speech transcript. This view resets for each new dictation.

## Optional local language models

Speech models recognize audio. A separate optional language model edits the resulting text.

In **Models → Text polishing**, configure a compatible chat-completions endpoint and model name. **Find models** lists models exposed by that server. Ollama cloud entries ending in :cloud are excluded from discovery.

For a local Ollama model:

~~~sh
ollama pull qwen2.5:1.5b
~~~

Endpoint: http://localhost:11434/v1/chat/completions
Model: qwen2.5:1.5b

LM Studio and other compatible servers can expose different local models. Those servers load GGUF or other model formats; wisprM uses their API.

Polishing is off by default. Only transcript text is sent to the configured endpoint; audio remains local. Remote endpoints require HTTPS; loopback may use HTTP. API keys are scoped to the normalized server origin, including port, in macOS Keychain. **Previously saved unscoped keys are not reused: save the key again for its server.**

Turning polishing off remains available during capture/transcription and cancels pending polishing. Text already transmitted cannot be recalled. Server/model controls and discovery are disabled during active dictation; changing a destination cannot silently redirect an existing capture.

Responses are capped before buffering/JSON decoding, generation is bounded, and incomplete/reasoning/tool responses are rejected. Failure preserves conservative local cleanup. Polishing quality still depends on the model; the original transcript remains available.

## Resource limits and privacy

- Microphone capture stops at a monotonic/frame-based **three-minute** budget.
- Imported audio is limited to **100 MiB input** and **10 minutes decoded audio**.
- Decoding is streamed; inference uses windows of at most **30 seconds**.
- Supported containers: WAV, CAF, AIFF/AIF/AIFC, M4A/MP4, MP3, FLAC, OGG/OPUS, WEBM/WEBA, AAC. Media imports use the audio track.
- Multi-channel input is metered across channels. Meter updates are coalesced into a small observed view.
- Cancellation supervises the owned worker/decoder process group and waits before restarting it.
- Temporary audio/chunks use owner-only permissions and are explicitly tracked and deleted. Normal quit waits for cleanup; deletion failures are shown rather than reported as success. Crash leftovers are cleaned on the next launch.
- History is opt-in, limited to 30 items, and deleted when disabled. Filesystem failures are visible and can be retried.
- No camera, screen capture, analytics, or automatic cloud transcription.

## Build and test

Requires Xcode / Command Line Tools with Swift 5.9 or newer.

~~~sh
swift test
python3 -m unittest discover -s Tests -p 'test_*.py'
bash scripts/build.sh
open dist/wisprM.app
~~~

The script builds the native bundle, generates original artwork, and signs ad hoc. This is a local build; Developer ID signing/notarization and broad application compatibility remain separate validation work.

Runtime setup uses a fully pinned wheel-hash lock:

~~~sh
bash runtime/setup-runtime.sh "$HOME/Library/Application Support/wisprM/runtime" /absolute/path/to/python3.12
~~~

runtime/requirements.lock.txt locks all 62 packages from the verified runtime, with allowed wheel hashes. Installation requires binary wheels and hash verification; it does not perform an unpinned pip upgrade. scripts/lock-runtime.py regenerates locks from an explicitly selected verified environment and official package metadata.

Cached-model integration checks:

~~~sh
python3 Tests/integration_transcription.py --engine Whisper --model mlx-community/whisper-tiny
python3 Tests/integration_transcription.py --engine Parakeet --model mlx-community/parakeet-tdt-0.6b-v3
swift run WisprCheck http://localhost:11434/v1/chat/completions qwen2.5:1.5b
~~~

The inference checks force offline mode and isolate their temporary recordings. Download a model through Models first if it is not cached. See verification/README.md for completed checks and remaining validation limits.

## Source and dependencies

Sources/WisprM contains the native app, capture, supervised worker, secure settings, insertion, and owned data cleanup. Sources/WisprCore contains formatting and privacy/import policies plus the bounded text-model client. runtime contains the original streaming worker, decoder, installer, and dependency/model locks.

Public dependencies include [MLX Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper), [Parakeet MLX](https://github.com/senstella/parakeet-mlx), imageio-ffmpeg, and their dependencies. Model weights retain their authors' licenses. The text client uses a compatible chat-completions API, such as [Ollama's API](https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx).
