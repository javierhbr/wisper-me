# Mobile verification

Validated on Apple Silicon (M3 Max), Xcode 26.5 / Swift 6.3, with the installed iOS 26.5 iPhone 17 Pro simulator. Work completed on 2026-10-23 local time / 2026-10-24 UTC.

## Passed

- **Simulator app and embedded keyboard build:** Debug, arm64, with ad-hoc signing and strict sealed-bundle verification. Both compiled Info plists and simulator entitlements use the same App Group.
- **Physical iPhone target build:** Release arm64 app and embedded keyboard compiled successfully. This output is unsigned; it was not installed on a phone. The app bundle is approximately 53 MB before speech or text-model downloads.
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
- Local MLX language-model inference on a physical iPhone. A real simulator attempt exposed unsupported Metal architecture/shared-heap behavior in the pinned backend. The app now rejects this operation safely in Simulator before entering MLX; the device build retains the native implementation. No simulated or canned LLM response substitutes for it.
- A live remote model-server request from the iPhone app. Shared HTTP transport/privacy behavior is covered by the existing core tests.
- Live typing/insertion by the keyboard in other host applications. The extension compiles, its read-only shared-container design is supported by Apple's documentation, and main-app shared-container access was observed. Secure fields and host apps that reject custom keyboards remain unsupported by iOS.
- App Store acceptance, completed distribution/development provisioning, or TestFlight deployment. USB follow-up found an existing Apple Development identity and configured its team only in the ignored local signing file; no new account was authenticated.

## USB readiness follow-up

Xcode detected a paired, available iPhone 16 Pro running iOS 26.6.2 with Developer Mode already enabled. It was visible over the local network, not USB. Existing local development profiles were checked, but the wildcard profile lacks the App Groups entitlement required by the app and keyboard. Automatic provisioning/device registration was blocked by approval review pending explicit authorization to modify Apple Developer account records. No provisioning or registration changes were made and no app was installed on the phone.

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
