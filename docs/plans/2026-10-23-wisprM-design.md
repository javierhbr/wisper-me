# wisprM design

## Product behavior

A native menu-bar dictation assistant with an original SwiftUI/AppKit interface. Control–Option–Space captures speech without activating the app. The nonactivating panel shows a microphone meter, elapsed time, and processing state. Captures finish on the second shortcut or automatically at three minutes.

Recognition is local. A persistent, isolated Python worker loads MLX Whisper Tiny or Parakeet TDT 0.6B v3 and accepts JSON-line requests. Users can select compatible model IDs or absolute local model folders; Whisper also offers Tiny, Base, and Small presets. Explicit preparation downloads weights. Subsequent inference uses the resolved local model path. Unloading terminates the worker and releases model memory.

AVAudioEngine writes a temporary owner-only CAF file, which is removed after processing or cancellation. The app also supports deliberate audio-file import without deleting originals.

Conservative local formatting runs first. Optional text polishing uses a user-selected model served by Ollama, LM Studio, or a compatible chat-completions endpoint. The default endpoint is loopback. Remote HTTP, URL credentials, and query strings are rejected. Credentials are stored separately in Keychain. Polishing failure preserves local output; the original transcript remains available for comparison.

## Integration boundaries

The Carbon shortcut is registered once and reports conflicts. Automatic insertion requires Accessibility, the original foreground application, and the original focused field. Secure text fields are excluded. Direct AXSelectedText insertion is preferred; custom editors may use a clipboard-preserving Paste fallback. A focus change retains text in the scratchpad instead of inserting into a different destination.

A session identifier rejects late inference results after cancellation. Settings are snapshotted at capture start. History is optional, local, and capped at 30 entries. The app has no screen capture, camera access, analytics, or cloud transcription.

## Delivery

Swift Package Manager builds the native app and a small validation CLI. A build script generates original artwork, creates an app bundle, and signs it ad hoc. The MLX runtime is installed separately in the user's Application Support directory. The supported target is Apple Silicon with macOS 14 or later.

Verification covers formatter and network policy behavior, worker errors and framing, real speech inference, local text polishing, and the packaged native app's audio-import pipeline. Microphone and cross-app automation verification require user-approved macOS privacy permissions. Distribution notarization and Developer ID signing are separate from the local build.
