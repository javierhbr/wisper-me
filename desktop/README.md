# wisprM — macOS

Run the commands in this document from the desktop/ directory. The repository root also forwards desktop Make commands.

An original native macOS voice-to-text app using SwiftUI/AppKit and local MLX speech models. No Wispr Flow code, files, assets, protocols, or branding are included.

The native iPhone app is in [wisprM-iOS](../wisprM-iOS/README.md), with its own Xcode project, Makefile, model runtimes, and transcript keyboard extension. It shares our formatting and privacy code while keeping the Mac application separate.

## Requirements

- Apple Silicon Mac running macOS 14 or later.
- Xcode 15+ or compatible Command Line Tools, providing Swift 5.9+ and make.
- Python **3.12 or 3.13**. The locked runtime does not support other Python versions.
- Internet access for the first runtime installation and model download. Cached speech models work offline.

Check your tools:

~~~sh
xcode-select -p
xcrun swift --version
make --version
python3 --version
~~~

If developer tools are missing, run xcode-select --install and finish Apple's installation. If python3 is another version, use a supported executable with every relevant Make command:

~~~sh
make install PYTHON=python3.13
~~~

PYTHON accepts an executable name or full path, including paths containing spaces. It is not a shell command with extra arguments.

## Build and install locally

Run commands from the repository root:

~~~sh
make install
make setup-runtime
make open
~~~

- **make install** builds, generates the original icon, signs and verifies the app, then installs it at **~/Applications/wisprM.app**. No sudo is needed.
- **make setup-runtime** installs the separate, hash-locked Python/MLX environment. It downloads packages and may take several minutes. Skip it if Models already reports that the runtime is installed.
- **make open** launches the installed app.

In **Models**, choose Whisper or Parakeet and select **Download & load model**. This is the explicit model-download step; installing the app does not download model weights.

If you need a specific Python:

~~~sh
make install PYTHON=/absolute/path/to/python3.12
make setup-runtime PYTHON=/absolute/path/to/python3.12
make open
~~~

### Update an existing installation

Quit the installed wisprM app, update the source, then run:

~~~sh
make test
make install
make open
~~~

The installer verifies both the source bundle and its staged copy before replacing an existing wisprM bundle. It refuses unrelated apps, app symlinks and running installed copies. A failed replacement restores the previous bundle when possible; a failed rollback retains the previous app and reports its path.

Installing or updating the bundle preserves settings, history, credentials, the runtime and downloaded models. Run make setup-runtime again when updating the runtime dependency lock.

### Choose another install directory

INSTALL_DIR is the directory containing the app, not the app bundle itself:

~~~sh
make install INSTALL_DIR="$HOME/Applications/Local Tools"
make open INSTALL_DIR="$HOME/Applications/Local Tools"
~~~

Use the same INSTALL_DIR when opening the app. Choose an absolute directory you can write to; /Applications may require administrator permissions.

## Make target reference

Running make without a target builds the app.

| Command | Result |
| --- | --- |
| make / make build | Build and ad hoc sign dist/wisprM.app; verify its signature after worker startup |
| make install | Build and install in ~/Applications, or INSTALL_DIR |
| make open | Open the installed app; does not build or install |
| make run | Build and open the development copy in dist |
| make test | Run all Swift and Python regression tests |
| make swift-test | Run the Swift tests |
| make python-test | Run the Python tests |
| make verify | Verify the existing development bundle and bundled worker without loading models |
| make setup-runtime | Install/update the locked runtime in Application Support |
| make clean | Remove only generated .build and dist outputs; quit the development app first |
| make help | Show targets and variable overrides |

PYTHON defaults to python3. INSTALL_DIR defaults to ~/Applications. Runtime setup uses the app's standard ~/Library/Application Support/wisprM/runtime location.

make clean does not uninstall the app or remove user data, credentials, the runtime or cached models. Keep source files and runtime lock files in version control.

Quit a running development copy before make run to use a new build; macOS otherwise activates the existing process. Run one Make invocation at a time while packaging the app.

## Daily use

1. Open wisprM and load a speech model in **Models**.
2. Allow microphone access when you start dictation.
3. Enable Accessibility in **Settings** for direct insertion into supported text fields.
4. Focus a text field and press **Control–Option–Space**.
5. Speak naturally, then press the shortcut again to finish.

Every completed transcript is copied to the clipboard and remains available for **Command–V**, including when direct insertion is disabled or unavailable. Starting from wisprM's window writes to its scratchpad.

Direct insertion requires a verified, editable, unprotected Accessibility element. There is no global keyboard/Paste synthesis. If focus changes or an editor rejects direct insertion, use deliberate Command–V.

**Import audio…** / Command–O transcribes a supported existing audio file without deleting the original. Microphone capture stops at three minutes. Imports are limited to 100 MiB and ten minutes of decoded audio.

wisprM appears in the Dock and Command–Tab while running. Click its Dock icon to reopen the window, or use the menu-bar icon to open wisprM or start/finish dictation. Closing its window keeps the app running in the Dock and menu bar; choose **Quit wisprM** or press Command–Q to exit.

## Choose a speech model

| Engine | Initial model | Alternatives |
| --- | --- | --- |
| Whisper | mlx-community/whisper-tiny, 39M parameters | Tiny / Base / Small presets; compatible MLX weights |
| Parakeet | mlx-community/parakeet-tdt-0.6b-v3, 0.6B parameters | Compatible Parakeet MLX weights |

The Base and Small repositories are mlx-community/whisper-base-mlx and mlx-community/whisper-small-mlx. Default revisions are pinned in runtime/models.lock.json.

The model selector shows download sizes for each pinned preset:

| Preset | Download size |
| --- | ---: |
| Whisper Tiny | 74 MB |
| Whisper Base | 144 MB |
| Whisper Small | 481 MB |
| Parakeet TDT v3 | 2.51 GB |

These are decimal file sizes, not memory requirements. Values include the files selected by the runtime's download filter, from Hugging Face repository metadata checked on 2026-10-23: [Tiny](https://huggingface.co/mlx-community/whisper-tiny/tree/78c52ab98ca87f570bc57ad852e15ef7060f9f76), [Base](https://huggingface.co/mlx-community/whisper-base-mlx/tree/1e3e249fb8d01c655324bd6841b1deadffd6d04c), [Small](https://huggingface.co/mlx-community/whisper-small-mlx/tree/45f3915923c7a79a5a5b5a7d909d39aeb0e5630e), [Parakeet](https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3/tree/ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15).

Select a preset to see its full local location, cache status, and measured local file size. **Show in Finder** opens an existing folder; **Refresh** checks it again after external changes. Before downloading, the panel shows the expected destination. The default cache is `~/.cache/huggingface/hub`; `HF_HUB_CACHE`, `HUGGINGFACE_HUB_CACHE`, `HF_HOME`, and `XDG_CACHE_HOME` overrides are respected. Custom folders show their own path and measured file size; unknown remote downloads are labelled as unknown. Local file sizes follow snapshot symlinks to their targets and do not represent unique physical disk allocation across shared snapshots.

Cached pinned weights load without a network request. A cache miss downloads the selected model. Custom remote IDs can specify an immutable revision as repo/name@<40-character-commit>; absolute local model folders are also supported.

Whisper Tiny emphasises speed and size. Parakeet 0.6B is larger. Accuracy varies by model, language and recording. Recognition starts after capture finishes; partial streaming transcripts are not shown.

Use **Unload** to release the loaded speech worker. The last successfully loaded model is restored when the app next starts.

## Formatting and original text

Names, URLs, email addresses, paths and backtick code retain their internal spelling and punctuation. Literal words such as “colon” are preserved.

**Interpret spoken punctuation commands in English** is off by default. Enable it in Settings for phrases such as “new paragraph”, “comma” or “question mark”. Select English when using these commands with Parakeet.

Local cleanup handles unambiguous English hesitations and spacing. Optional language-model polishing provides professional, casual or bullet-list rewriting. **Show original** lets you compare and copy the original transcript; the view resets for each new dictation.

## Optional local text polishing

Speech models recognise audio. A separate optional language model edits the resulting text.

In **Models → Text polishing**, enter a compatible chat-completions endpoint and model name. **Find models** lists models exposed by that server. Ollama entries ending in :cloud are excluded from discovery.

For a local Ollama model, with Ollama already installed and running:

~~~sh
ollama pull qwen2.5:1.5b
~~~

Configure:

| Setting | Value |
| --- | --- |
| Endpoint | http://localhost:11434/v1/chat/completions |
| Model | qwen2.5:1.5b |

LM Studio and other compatible servers can expose different local models. Those servers load GGUF or other formats; wisprM uses their API.

Polishing is off by default. Only transcript text is sent to the configured endpoint; audio stays local. Remote endpoints require HTTPS, while loopback may use HTTP. API keys are stored in macOS Keychain and scoped to server origin, including port. **Keys saved before server scoping must be saved again for their server.**

Turning polishing off remains available during capture/transcription and cancels pending polishing. Text already transmitted cannot be recalled. Server/model editing and discovery are disabled during active dictation.

Responses and generated output are bounded. Incomplete or malformed responses retain local cleanup. Polishing quality depends on the model; the original transcript remains available.

## Data locations and privacy

| Data | Default location |
| --- | --- |
| Installed app | ~/Applications/wisprM.app |
| Development app | dist/wisprM.app |
| Runtime | ~/Library/Application Support/wisprM/runtime |
| Optional history | ~/Library/Application Support/wisprM/history.json |
| Temporary recordings | ~/Library/Application Support/wisprM/Recordings |
| Model weights | Hugging Face cache, normally ~/.cache/huggingface/hub |
| Preferences | macOS defaults domain com.wisprm.desktop |
| Server credentials | macOS Keychain, service com.wisprm.desktop.polishing |

The app itself is small; the separate MLX/Python runtime and weights use substantially more disk space. The initial verified runtime occupied approximately 1.4 GB before model weights.

Temporary recordings/chunks use owner-only permissions. Completion, cancellation and normal quit clean up owned audio; failures remain visible. Crash leftovers are cleaned on the next launch. Imported originals are never deleted.

History is opt-in, limited to 30 items and deleted when disabled. No camera, screen capture, analytics or automatic cloud transcription is included.

Supported import containers are WAV, CAF, AIFF/AIF/AIFC, M4A/MP4, MP3, FLAC, OGG/OPUS, WEBM/WEBA and AAC. Media imports use the audio track. Decoding is streamed and inference windows never exceed 30 seconds.

## Troubleshooting

**Python version rejected:** pass PYTHON=python3.12, PYTHON=python3.13 or a full supported executable path.

**Developer tools missing:** run xcode-select --install, complete installation, then retry make build.

**Permission denied during installation:** use the default ~/Applications directory or another writable INSTALL_DIR.

**Installed app is running:** quit it before make install. Installation does not forcibly terminate an app or discard its transcript.

**Interrupted installation:** first ensure no installer is running. A stale .wisprM.install.lock in INSTALL_DIR can then be removed. If a failure reports a retained previous.app inside .wisprM-stage-*, recover that bundle before removing the staging directory.

**Runtime installation failed:** check the network and supported Python, then retry make setup-runtime. Keep hash verification enabled; do not remove the lock file to bypass a failure.

**Model will not load:** check the selected engine, model ID or local folder, and network access for an uncached model. Default snapshots are revision-pinned.

**Microphone or insertion unavailable:** authorise wisprM in macOS System Settings → Privacy & Security → Microphone / Accessibility. A rebuilt ad hoc app may need reauthorisation. Unsupported editors still work through the clipboard.

**Shortcut unavailable:** another app may own Control–Option–Space. The UI reports registration failure; the Dictate button remains available.

**Signature check failed:** run make clean after quitting the development app, then make build. The build verifies the signature after starting the bundled worker; Python is prevented from writing bytecode inside the sealed bundle.

This is a local ad hoc signed build, not a Developer ID signed/notarised distribution. Production distribution signing is separate work.

## Tests and verification

~~~sh
make test
make build
make verify
~~~

Model-free tests cover formatting, live privacy-off, server scoping, response limits, cancellation, process descendants, all-channel audio, storage failures, installation rollback and sealed-bundle startup.

Optional integration checks require the selected weights to be cached:

~~~sh
python3 Tests/integration_transcription.py --engine Whisper --model mlx-community/whisper-tiny
python3 Tests/integration_transcription.py --engine Parakeet --model mlx-community/parakeet-tdt-0.6b-v3
swift run WisprCheck http://localhost:11434/v1/chat/completions qwen2.5:1.5b
~~~

The speech checks force offline mode and isolate temporary audio. The text check uses the configured local server. See [the verification report](verification/README.md) for actual results and limits.

runtime/requirements.lock.txt pins the complete verified environment with wheel hashes; runtime/models.lock.json pins default model revisions. scripts/lock-runtime.py regenerates these from an explicitly selected verified environment and official metadata. Normal setup uses the existing locks.

## Remove or reset the app

Quit wisprM and move the installed bundle to Trash. With a custom installation, remove that directory's wisprM.app. make clean only removes development outputs.

Removing the bundle retains runtime, models, preferences, history and Keychain items. Delete history through Settings. To remove remaining local data, use Finder to move the relevant paths above to Trash. Only remove shared Hugging Face snapshots if no other app needs them. Manage saved server keys in Keychain Access.

To reset preferences after quitting:

~~~sh
defaults delete com.wisprm.desktop
~~~

## Source and public dependencies

Sources/WisprM contains the native app, capture, supervised worker, settings, insertion and owned-data cleanup. Sources/WisprCore contains formatting/privacy/import policies and the bounded text client. runtime contains the original worker, decoder, installer and locks. scripts provides packaging, local installation and verification.

Public dependencies include [MLX Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper), [Parakeet MLX](https://github.com/senstella/parakeet-mlx), imageio-ffmpeg and their dependencies. Model weights retain their authors' licences. The text client follows a compatible chat-completions API such as [Ollama's API](https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx).
