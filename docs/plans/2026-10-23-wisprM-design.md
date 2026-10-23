# wisprM design

## Native app and inference boundary

An original SwiftUI/AppKit menu-bar dictation assistant. Control–Option–Space toggles microphone capture without activating the app. A nonactivating panel displays the isolated, coalesced meter and phase. Capture has a three-minute monotonic/frame budget and meters every channel.

A persistent Python worker loads local MLX Whisper or Parakeet weights. Startup establishes an owned process group and emits a readiness handshake. Native code verifies the child PID/group against the kernel, bounds JSON lines, owns request continuations/watchdogs, supervises termination, and awaits exit before replacement work. Decoders inherit the worker group.

The worker validates file/container and input-size limits, streams 16kHz mono PCM under a decoded-duration budget, and uses inference windows of at most 30 seconds. Whisper consumes arrays; Parakeet consumes owner-only temporary WAV windows. Default model revisions and all runtime dependencies are locked. Cached pinned models load offline first; custom models can specify immutable commits or local folders.

## Privacy and output

Recording preferences snapshot intent but cannot acquire new consent. Live privacy-off overrides the capture snapshot and cancels pending polishing. Endpoint/model editing and discovery cannot overlap an active dictation. Capture, discovery, setup, and polishing have separate task ownership.

The persistent bounded HTTP client rejects redirects, excessive headers/body size, incomplete generation, tool/refusal responses, and malformed reasoning blocks. Its delegate never retains its owner; shutdown drains requests and invalidates the session. Credentials are bound to normalized scheme/host/effective-port; the former unscoped Keychain account is never reused.

Local cleanup preserves structured spans and mixed-case names. Spoken command interpretation requires explicit opt-in. Each new transcript generation resets original-view state.

Completed text remains on the clipboard by user request. Direct AX insertion requires the original foreground process/field, readable unprotected editable attributes, settable selected text, and bounded AX messaging on the exact objects used. Global Paste synthesis is excluded. Uncertain/custom fields use deliberate manual Paste.

## Data ownership and termination

LocalDataStore explicitly tracks captured recording URLs, recognizes only ENOENT as already deleted, retains failed-deletion ownership, and cleans known worker chunks. History mutation reports actual filesystem success. Imported originals are never owned or deleted.

Normal termination returns terminateLater, cancels owned work, invalidates networking, awaits worker/decoder exit and task cleanup, then replies to AppKit. Cleanup errors cancel normal termination and remain visible. Crash artifacts are handled during the next launch.

## Delivery and verification

Swift Package Manager builds an Apple Silicon/macOS14+ app plus isolated unit/workflow tests. Packaging creates original artwork and an ad hoc signed local bundle.

Regression coverage includes live consent revocation, independent cancellation, synthetic clipboard completion, quit cleanup, storage failures, all-channel audio, deadlines, process descendants/watchdogs, response bounds, scoped origins, malformed output, text integrity, preference migration, and format limits. Tests avoid user audio/clipboard/Keychain. Real cached Whisper and Parakeet inference is checked offline on generated speech.

Native Accessibility behavior across real third-party applications, physical input-device coverage, Intel support, production distribution signing/notarization, and benchmark claims remain outside the automated verification boundary.
