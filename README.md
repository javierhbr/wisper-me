# wisprM

An original native macOS voice-to-text app. SwiftUI and AppKit provide the interface; local MLX models handle speech. No Wispr Flow source, files, assets, protocols, or branding are included.

## Open the app

Open **dist/wisprM.app**. This workspace includes the built, ad hoc signed app.

1. In **Models**, install the local runtime if needed.
2. Choose **Whisper** or **Parakeet**, then **Download & load model**.
3. Allow microphone access when starting dictation.
4. In **Settings**, enable Accessibility for insertion into other apps.
5. Focus a text field and press **Control–Option–Space**. Speak, then press it again to transcribe and insert.

Starting from wisprM's window writes to its scratchpad. **Import audio…** / Command–O transcribes an existing audio file without a microphone. Imported files are never deleted.

### Local speech choices

| Engine | Initial model | Other choices |
| --- | --- | --- |
| Whisper | mlx-community/whisper-tiny, 39M parameters | Tiny / Base / Small presets; compatible MLX Whisper model ID or absolute local folder |
| Parakeet | mlx-community/parakeet-tdt-0.6b-v3, 0.6B parameters | Compatible Parakeet MLX model ID or absolute local folder |

Whisper Tiny emphasizes speed and disk use; larger models can improve accuracy. Parakeet 0.6B is the smallest verified Parakeet preset here, but is substantially larger than Whisper Tiny. Models download from Hugging Face when explicitly loaded. After preparation, transcription uses local weights. A previously loaded selection is restored at the next launch.

MLX requires **Apple Silicon**. This build targets **macOS 14+**. Installing the isolated runtime requires an existing **Python 3.10+** installation. The app checks common Homebrew and pyenv locations. No Python installation is required again on this machine: its runtime is already installed.

The native bundle is approximately 1.8 MB. The Python/MLX runtime and downloaded model weights require additional disk space; the runtime installed for validation occupies approximately 1.4 GB. This is not an Intel build.

## Use any compatible local language model

Speech models recognize audio. A separate optional language model rewrites the transcript.

In **Models → Text polishing**, enable polishing and enter your server endpoint and model name. **Find models** queries its compatible model-list API. Hosted Ollama entries ending in :cloud are excluded from automatic discovery.

For Ollama:

~~~sh
ollama pull qwen2.5:1.5b
~~~

Use endpoint http://localhost:11434/v1/chat/completions and model qwen2.5:1.5b. That model was verified locally. LM Studio and other servers with a compatible chat-completions API can use their own served model names. GGUF or other model files are loaded by the server, not directly by wisprM.

Polishing is off by default. The app sends transcript text to the configured endpoint; it does not send audio. HTTPS is required for remote hosts; HTTP is allowed for loopback only. Optional API keys are stored in macOS Keychain. Model quality varies: the very small Qwen 0.5B model changed meaning during a verification case, while 1.5B preserved that case. **Show original** lets you recover the original dictation after an edit. If polishing fails, local cleanup is retained.

## Behavior and privacy

- Menu-bar controls and a nonactivating recording panel.
- Control–Option–Space toggles capture without activating wisprM.
- A capture stops automatically at three minutes.
- Recognition runs after finishing capture; this build does not show streaming partial transcripts.
- Local cleanup handles filler words, spacing, spoken English punctuation, paragraphs, and bullet formatting.
- Automatic insertion checks the original application and focused field. If focus changes, output stays in wisprM for copying. Secure fields are excluded. Custom editors can use a clipboard/Paste fallback.
- Every completed transcript is copied to the clipboard, whether automatic insertion is enabled or not. The transcript remains available for Command–V until you copy something else.
- Accessibility permission is necessary for cross-app insertion. Individual applications can reject automation; universal compatibility has not been established.
- Temporary microphone audio is written with owner-only permissions and deleted after processing or cancellation. Crash leftovers are removed on the next launch.
- Local history is opt-in, limited to 30 items, and deletable.
- No camera, screen capture, analytics, or automatic cloud transcription.

## Build from source

Requires Xcode / Command Line Tools with Swift 5.9 or newer.

~~~sh
swift test
python3 Tests/test_worker_protocol.py
python3 Tests/test_installer.py
bash scripts/build.sh
open dist/wisprM.app
~~~

The build generates its original icon and signs locally. This is an **ad hoc signed local build**, not a Developer ID signed or notarized distribution release. Rebuilding can require macOS permissions to be reauthorized.

Optional runtime setup from the project directory:

~~~sh
bash runtime/setup-runtime.sh "$HOME/Library/Application Support/wisprM/runtime" /absolute/path/to/python3
~~~

Real inference checks, including model download if needed:

~~~sh
python3 Tests/integration_transcription.py --engine Whisper --model mlx-community/whisper-tiny
python3 Tests/integration_transcription.py --engine Parakeet --model mlx-community/parakeet-tdt-0.6b-v3
swift run WisprCheck http://localhost:11434/v1/chat/completions qwen2.5:1.5b
~~~

See verification/README.md for what was actually checked and what still needs a live permission-enabled check.

## Source layout

- Sources/WisprM: native UI, microphone capture, model worker management, shortcut, insertion, settings, and history.
- Sources/WisprCore: conservative formatting, model configuration, endpoint policy, and text-model client.
- runtime: original JSON-line worker and isolated runtime installer.
- Tests: unit, protocol, and real inference checks.
- scripts: app packaging and original icon generation.

## Third-party components

wisprM's application code and artwork were written for this project. It uses Apple's system frameworks and separately installed public dependencies: [MLX Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper), [Parakeet MLX](https://github.com/senstella/parakeet-mlx), imageio-ffmpeg, and their dependencies. Model weights retain their respective authors' licenses. The optional text integration follows [Ollama's compatible API](https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx).
