# Mobile verification

Validated on Apple Silicon (M3 Max), Xcode 26.5 / Swift 6.3, with the installed iOS 26.5 iPhone 17 Pro simulator. Work completed on 2026-10-23 local time / 2026-10-24 UTC.

## Passed

- **Simulator app and embedded keyboard build:** Debug, arm64, with ad-hoc signing and strict sealed-bundle verification. Both compiled Info plists and simulator entitlements use the same App Group.
- **Physical iPhone target builds and installation:** unsigned Release arm64 and development-signed Debug app/keyboard built successfully. Signed bundle verification passed, and CoreDevice confirmed USB installation. The unsigned Release bundle is approximately 53 MB before model downloads.
- **11 mobile Swift tests, run on the Mac host:** audio resampling through EOF, stereo downmixing, oversized audio rejection, captured polishing consent, reasoning-output filtering, transcript expiry/future-date/size limits, bounded history, defaults, and compatible-folder copying/symlink rejection.
- **2 Python project tests:** signing IDs/team/App Group survive repeated generation, and project generation is deterministic.
- **Existing Mac regression suite:** 55 Swift tests and 25 Python tests, all passing after adding the iOS deployment platform to the shared package.
- **Actual Whisper Tiny inference inside the iPhone app:** generated speech was decoded, recognized, and formatted using the native production services, with an empty error result.
- **Actual Parakeet TDT 0.6B v3 inference inside the iPhone app:** the exact `.v3` Core ML model recognized the same generated speech, including after the cache-path/offline-local-loader fix.
- **App Group available in Simulator:** both integration reports recorded `sharedContainer: true`.
- **Source review:** correctness, architecture, and security reviewers independently checked their reported fixes and approved their bounded follow-up scopes. Synthesis introduced no additional blocking issue. This was source review, not independent device testing.

Both native speech engines produced:

> The quick brown fox jumps over the lazy dog.

The final cached integration runs reported approximately 1.76 seconds for Whisper Tiny and 4.64 seconds for Parakeet. Those totals include loading and application processing in this simulator on this Mac. They are functional checks, not iPhone latency, battery, thermal, or accuracy benchmarks.

## Bugs found and fixed during validation

- AVAudioFile could throw an opaque Foundation error when read again after its final frame. The converter now checks remaining frames before reading; the regression test covers resampling through EOF.
- AVAudioConverter defaults to channel remapping, which discarded speech present only on the second stereo channel. Explicit downmixing and a second-channel test preserve that audio.
- Background-task expiry now ends its assertion immediately before cancelling inference; deferred cleanup can safely repeat the operation.
- Local-polishing cleanup awaits model unloading before propagating cancellation.
- Failed recording startup and partial audio/model imports remove their owned temporary files. Imports copy off the main actor while retaining scoped access.
- Project generation preserves local signing configuration. Model cleanup can remove partial downloads that never received an installation receipt.
- Integration-runner teardown terminates the owned app, reaps its console launcher, closes handles, and removes its generated input on both success and failure.

## Explicitly not verified

- Physical iPhone microphone capture, phone-call/Bluetooth interruptions, lock-screen/background completion, memory pressure, battery, thermals, and long recordings.
- Whisper Base/Small inference. Their real native variants are wired into the same WhisperKit loader, but only Tiny was exercised end to end.
- Local MLX polishing across other models or long transcripts. Qwen2.5 0.5B 4-bit completed the generated-speech check on the physical iPhone, as recorded below. Simulator MLX remains explicitly unsupported by the pinned backend; the app rejects it safely.
- A live remote model-server request from the iPhone app. Shared HTTP transport/privacy behavior is covered by the existing core tests.
- Live typing/insertion by the keyboard in other host applications. The extension compiles, its read-only shared-container design is supported by Apple's documentation, and main-app shared-container access was observed. Secure fields and host apps that reject custom keyboards remain unsupported by iOS.
- App Store acceptance, distribution provisioning, or TestFlight deployment. Development provisioning and USB installation have been verified separately below.

## USB readiness follow-up

After the Account Holder accepted Apple's pending Program License Agreement, automatic development provisioning succeeded. Both the app and keyboard built with the configured signing team. The app profile explicitly contains the required App Group and the connected phone's UDID; `codesign --verify --deep --strict` passed with access to the local signing trust store. Local signing identifiers remain in the ignored signing configuration.

Installation succeeded over USB: CoreDevice confirmed `com.javierhbr.wisprm` installed with the embedded keyboard. Both provisioning profiles contain the same required App Group and the phone's UDID. The initial locked-screen test launch was denied by iOS; after unlocking, all three generated-speech checks completed on the physical iPhone 16 Pro (iOS 26.6.2):

| Test | Observed output | Total time |
| --- | --- | --- |
| Whisper Tiny | The Quick Brown Fox jumps over the lazy dog. | 17.19 s |
| Parakeet TDT 0.6B v3 | The quick brown fox jumps over the lazy dog. | 23.31 s |
| Whisper Tiny + local MLX Qwen2.5 0.5B 4-bit polishing | The Quick Brown Fox jumps over the lazy dog. | 16.53 s |

Each report returned an empty error and `sharedContainer: true`. The polishing run unloaded speech recognition before loading and running the real MLX text model; no server or canned response was used. These are single fixture runs including model loading and any required downloads, not latency benchmarks. Parakeet's first download attempt reported `cancelled`; the diagnostic retry completed successfully. No general reliability claim is implied by that successful retry.

Reports are retained locally in ignored `.build/phone-whisper-tiny.json`, `.build/phone-parakeet-v3.json`, and `.build/phone-whisper-tiny-polished.json`. The Debug-only fixture route temporarily suppresses the idle timer during inference and restores its previous state afterwards. Fixture audio is deleted by the normal processing cleanup; tests do not record the microphone or write the clipboard. Physical microphone capture, clipboard paste, host-app keyboard insertion, interruptions, battery, and thermal behavior remain unverified.


## Reproduce

```sh
cd wisprM-iOS
make test
make build
make device
python3 scripts/integration-transcription.py --model whisper-tiny
python3 scripts/integration-transcription.py --model parakeet-v3
```

The integration script generates speech rather than recording the microphone, never reads personal audio, and suppresses clipboard writes for the debug fixture run. Fixture runs use a separate UserDefaults suite and separate history, recordings, and shared-transcript locations; only reusable model weights are shared with normal runs. Reports and full build logs are stored in the ignored `.build/` directory. Dependencies and models require an initial download; no model weights or generated build products are committed.
