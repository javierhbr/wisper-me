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


## Apple Intelligence polishing (2026-10-24)

- The mobile suite passed: 12 Swift tests and 2 Python project-generation tests. The new consent test first failed because the provider did not exist, then passed after implementation. It covers captured consent, provider changes, unrelated MLX/server settings, persistence, and the unchanged opt-in default.
- Simulator Debug and development-signed iPhone Debug builds passed. Strict signature verification passed for the final app and embedded keyboard. Mach-O inspection confirmed Foundation Models is weak-linked; calls and generated types are guarded for iOS 26. The project retains its iOS 17 deployment target; an actual iOS 17 device was not tested.
- Native Simulator UI inspection confirmed the new Apple Intelligence picker item and the Ready status text in Models. The framework's real system model completed an end-to-end Whisper Tiny test, correcting `She go to the story yesterday and buy two Apple.` to `She went to the store yesterday and bought two apples.` The cached run took 3.08 seconds including speech recognition and generation.
- An unsupported-language check using Parakeet v3 and selected Russian locale returned `appleIntelligenceAvailable: false`, `polishingCompleted: false`, and an explanatory language error. The recognized sentence remained byte-for-byte equal to `unpolishedText`. The integration driver deliberately exits nonzero for unavailable polishing; separate assertions verified this expected fallback result.
- The final signed update was installed on the physical iPhone 16 Pro. After the locked-screen launch blocker cleared, real Whisper Tiny → Apple Intelligence inference completed with no error, `polishingCompleted: true`, and shared-container access. It corrected `She go to the store yesterday and buy two Apple.` to `She went to the store yesterday and bought two apples.` Total time was 11.14 seconds, including model loading and first system-model use, not a steady-state benchmark. A subsequent physical Parakeet → Apple Intelligence check could not launch after the phone locked again; Parakeet recognition was previously verified on the phone, but that additional positive provider combination is not claimed as tested.

Reports remain in ignored `.build/integration-whisper-tiny-apple-intelligence.json`, `.build/integration-parakeet-v3-apple-intelligence.json`, and `.build/phone-whisper-tiny-apple-intelligence.json`. Tests use generated speech, isolated preferences/history/sharing, and the production polishing path; the report only marks polishing complete after the requested provider returns and its result is accepted. No microphone capture or clipboard writes occur during fixture tests. Physical background interruption, guardrail refusal, long-context failure, and other system-model availability states have not been exercised. Their failure paths preserve local cleanup in the coordinator.

## Cached speech-model restoration (2026-10-24)

The restart bug was reproduced in the normal Simulator app: Parakeet remained selected and its receipt showed 483.3 MB stored, but relaunching reset engine readiness and displayed **Choose a speech model**. Startup never loaded the saved selection; polishing also unloaded speech without letting recording restore it.

The fix automatically prepares the selected cached model on launch/foreground, distinguishes cached files from an engine loaded in memory, and reloads cached speech when recording starts after polishing or unloading. Startup and recording restoration explicitly pass `allowDownload: false`. Manual loading also discovers complete cached preset files when their receipt is missing. Imported models still require their saved receipt and valid local components. Selection is not silently changed to another cached preset.

Verified:

- `integration-relaunch.py --model parakeet-v3` and `--model whisper-tiny`: each prepared the real engine, terminated the app, and relaunched with only the startup-check flag. Both restored the saved selection, returned `ready: true` and `canDictate: true`, and recorded `downloadAllowed: false`. Both repeated successfully after clearing only the isolated test receipts. Large cached weight-file paths, sizes, and modification times remained unchanged throughout all four restores.
- Actual Whisper Tiny + Apple Intelligence processing still completed. After polishing unloaded speech (`loadedModel` empty), `canDictate` remained true, so **Start dictation** can prepare the cached engine instead of sending the user to model setup. This did not record a microphone.
- The existing 12 mobile Swift tests and 2 project-generation tests passed. Simulator Debug, signed iPhone Debug, and unsigned iPhone Release builds passed.
- The signed update installed on the physical iPhone. A real startup check restored saved Whisper Tiny and returned `ready: true`, `canDictate: true`, `cachedModel: true`, `downloadAllowed: false`, and an empty error. The isolated test process was terminated afterwards. A normal relaunch was requested, but iOS blocked activation after the phone locked again; the next manual launch uses normal preferences. No microphone or clipboard was used in this check.

Reports are in ignored `.build/relaunch-parakeet-v3.json`, `.build/relaunch-whisper-tiny.json`, and `.build/phone-model-restore.json`. Physical Parakeet startup, imported-model restoration, incomplete/corrupt-cache repair, and actual microphone capture after reloading were not separately exercised in this change.

## Parakeet recovery and microphone waveform (2026-10-24)

The user reported indefinite Preparing on cached Parakeet. The old path called synchronous `AsrModels.loadLocal`, including synchronous Core ML construction, on the speech actor. UI cancellation subsequently awaited cleanup on that same actor. The exact blocked native stack could not be captured because the phone locked before debugger attachment; an ANE/compiler root cause is not asserted.

The replacement is an original v3-only local adapter using public asynchronous `MLModel.load` and the SDK's public model initializer/component names. It does not use SDK repair/redownload behavior or global offline flags. A locked one-shot continuation returns on timeout/cancellation without waiting for an uncooperative native child; one pending reservation lasts until the native worker actually finishes. Generation checks prevent late engine adoption, and progress generations are invalidated at completion so late updates cannot overwrite another job. The 90-second deadline covers Parakeet native construction, not every download, Whisper load, or cleanup operation. Native framework work can outlive the UI deadline.

Validation passed:

- 17 mobile Swift tests and 2 project-generation checks, including five new metering/deadline tests. The deadline regression explicitly verifies the bounded call returns before the late native callback, then waits for callback cleanup. Early cancellation, success/error completion, bounded meter history, silence, and non-finite audio power are covered.
- Simulator Debug and signed iPhone Debug builds. Real Parakeet inference and both cache-only restart/missing-receipt checks still passed in Simulator.
- Actual Parakeet preparation/transcription completed on the physical iPhone with an empty error, a ready model, and the expected generated sentence. Total fixture time was 27.06 seconds after installation, including model preparation and transcription. This is one functional run, not a warm-start or energy benchmark. The final reviewed update was installed and launched normally afterwards.
- Uncle Senior re-reviewed the continuation, pending-job, stale-result, and progress-generation changes and found no remaining concrete blocker in that bounded scope.

The waveform is connected to `AVAudioRecorder.updateMeters` at up to 20 Hz only while recording is visible. It disables visual metering/timers when inactive or on another tab, publishes displayed duration at whole-second changes, skips unchanged histories, gives the timer tolerance, and resets at cleanup. Core audio recording remains unchanged and capped at three minutes. Hardware microphone visualization, interruptions during metering, and actual energy consumption were not separately measured; fixture tests use generated audio and never record the user's microphone.

## iPhone energy and security source review (2026-10-24)

Uncle Lead and Uncle Senior performed bounded read-only reviews. Graph tools were unavailable, so evidence uses exact source reads and searches. Neither measured battery drain, CPU utilization, thermals, or actual data leakage. Findings below are code behavior or policy gaps, not measured mWh savings:

| Priority | Finding | Status / suggested next step |
| --- | --- | --- |
| P1 | Unbounded synchronous cached Parakeet preparation and same-actor cleanup could strand Preparing/Cancelling. | Addressed by the async adapter, bounded waiter, one pending native job, and stale-result checks above. Framework work may still outlive cancellation. |
| P2 | Visual microphone metering continued when hidden and published duration every tick. | Addressed in the new waveform lifecycle: visible-only sampling, timer invalidation/tolerance, duration approximately 1 Hz. |
| P2 | ASR is unloaded around Apple/MLX edits and reloaded for later dictation/foreground use, even when returning only to History/Settings. Apple availability is checked after discarding ASR. | Addressed: availability checked first, ready speech retained for normal foreground Apple edits, hidden speculative loads cancelled, no foreground/History/Settings preloads after unloading, serialized pressure/background-idle cleanup. Actual battery/RAM impact remains unmeasured. See `App/MobileModel.swift` and `App/WisprMobileApp.swift`. |
| P2 | Automatic copying uses the general clipboard without local-only or expiry options. Keyboard insertion expiry does not apply to it. | Addressed: copies use device-local objects with expiration ten minutes after copying. Universal Clipboard eligibility is verified by API choice; no cross-device transfer was observed. See `App/MobileModel.swift` (`copy`). |
| P2 | Models are excluded from backup only after successful ASR preparation. Initial text-only downloads/imports or a first hanging load can precede that exclusion. | Addressed: owned model roots are created/excluded before downloads/imports and after recreation. Actual backups were not inspected. See `App/Storage.swift` and `MobileInference/.../NativeModels.swift`. |
| P3 | Every cached reload rescans model files despite an existing byte-count receipt. | Addressed: positive receipt byte counts are reused for the same validated canonical cache folder; missing receipts are measured once. See `App/MobileModel.swift` and `App/Storage.swift`. |
| P3 | Opt-in local history is file-protected but not excluded from OS backups. | Addressed: owned history/shared directories and atomic replacements are excluded from backup; existing files are migrated. File protection is not a device-only promise. See `MobileCore/.../Domain.swift` (`HistoryArchive`). |

Existing controls remain: HTTPS except explicit loopback, rejected redirects, origin-scoped device-only Keychain credentials, bounded imports/responses, captured polishing consent, explicit keyboard insertion, and no keyboard microphone/network access. No broad security rewrite is indicated by this review.

For a real energy comparison, use Release workloads on the phone, separate cold/warm starts, compare repeated short dictations with cleanup/Apple/MLX, compare visible/hidden metering, and record Low Power Mode, thermal state, and peak memory. Debug fixtures disable idle sleep while they run and are not battery benchmarks. Relevant Apple guidance: [timer use](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeTimerUse.html), [pasteboard options](https://developer.apple.com/documentation/uikit/uipasteboard), and [backup exclusion](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey).

## Integrated privacy and model-resource fixes (2026-10-25)

All findings in the source review above are addressed in the app. Apple availability is checked before changing ASR residency; normal foreground Apple edits retain ready speech. MLX inference stays sequential, while its explicit download action only caches files and completes the SDK snapshot to recover interrupted downloads. Cached speech receipts avoid rescans only for the same validated canonical directory. Hidden speculative preparation is cancelled; explicit downloads, recordings and requested work are preserved. Foreground returns do not warm an unloaded engine. Memory/thermal pressure and a one-shot 60-second background idle delay request serialized cleanup after active work finishes. The background task checks actual application state before unloading, and new speech preparation awaits the release owner.

Clipboard writes are device-local and expire ten minutes after copying. Model/support/history/shared directories are excluded before writes, existing owned files are migrated, and atomic replacements reapply the exclusion. This sets an OS backup policy; it does not delete previous backups or establish that every SDK/system cache is excluded.

Validated against the final source:

- 25 mobile Swift tests and 10 Python tests passed. Simulator Debug, signed iPhone Debug, and unsigned iPhone Release builds passed.
- Whisper Tiny and Parakeet v3 restored their cached selection with downloads forbidden. Positive receipts caused zero model-storage scans; clearing isolated test receipts caused one scan. Unloaded foreground/History/Settings scenarios each caused zero new preparations while retaining the ability to dictate from cache.
- Actual Simulator Whisper + Apple Intelligence completed with an empty error and speech still loaded. Parakeet + Russian reported Apple language unavailability while preserving local text and ready speech. Qwen 0.5B cache-only download completed without loading MLX or discarding ready Whisper. Reports are in ignored .build integration/relaunch/lifecycle JSON files.
- Independent correctness, architecture, and privacy/fixture reviews found no remaining blocker after fixes. Fixture cleanup checks ownership from official launch JSON before terminating its exact process and run in finally on success/failure.
- The final signed update installed on the authorized iPhone after an initial connection failure. Two generated-audio launch attempts were blocked by iOS because the phone was locked. No microphone or clipboard was used; no new physical inference success is claimed for this revision.

Actual battery drain, CPU/thermal improvements, peak memory, OS backups and cross-device clipboard transfer were not measured.

## Ten-minute recording and 9:30 warning (2026-10-25)

The iPhone recorder now stops at 600 seconds and schedules an original 0.55-second two-tone warning at 570 seconds, leaving thirty seconds to finish. Both capture and decoding use the shared RecordingLimits maximum. AVAudioPlayer uses its audio device clock, independent of waveform visibility and UI timers. Finish, Cancel, interruption, normal completion and failed startup stop/release the player. The chime uses the current audio route and media volume.

The generated-audio boundary regression accepted 600 seconds (9,600,000 mono samples) and rejected 601 seconds. The bundled WAV was inspected and included in successful Simulator/signed iPhone Debug/unsigned iPhone Release builds. Two independent source reviews approved the scheduling and cleanup paths. The installed update contains this feature.

A complete microphone recording through 9:30/10:00, the warning's physical timing/audibility and audio-route changes have not been exercised. Ten-minute recognition performance and battery use have not been measured. The latest physical generated-audio launches were blocked by the phone lock, as recorded above.

## On-demand idea rewriting (2026-10-25)

Rewrite idea is a separate manual action with optional directions, independent Apple/local/server provider selection, an Original/Rewrite preview, explicit acceptance or rejection, and one-level Undo. It remains usable with automatic grammar polishing off. Unaccepted proposals do not replace text, enter history, update keyboard publication, or copy to the clipboard. Acceptance uses existing delivery/privacy policies; Undo restores the exact source and removes the accepted revision's history entry.

Verified:

- Full suites passed: 58 root Swift tests, 36 mobile Swift tests, and 14 Python tests. The 11 new state tests cover retries, cancellation, stale generations, edited-source/ABA invalidation, bounds, acceptance, and Undo. Provider wire tests verify the distinct rewrite prompt, JSON-separated directions/source, combined input bounds, and guarded output parsing. All 16 provider tests passed again after final prompt changes.
- Simulator Debug, signed iPhone Debug, and unsigned iPhone Release builds passed. All three providers compile with the existing pinned dependencies; server behavior is covered through the injected HTTP test transport.
- Real Apple Intelligence fixtures in Simulator exercised automatic polishing off, cancelling before provider-task creation, generation, unchanged transcript/history/shared publication before acceptance, acceptance, and exact Undo restoration. All report assertions passed. The release-story fixture moved the tentative release suggestion first. Prompt instructions explicitly preserve modal force and every distinct fact/requested action, including secondary updates.
- The authorized iPhone passed a real generated-audio Apple Intelligence rewrite with all preview/accept/Undo/cancellation assertions. A subsequent local MLX rewrite launch was blocked by iOS because the phone locked; the new manual MLX flow is compiled but not claimed physically verified. No microphone or clipboard was used by fixtures.
- Simulator UI inspection exercised Original/Rewrite switching, Use rewrite, exact Undo restoration, and the provider/directions form at the default iPhone 17 Pro size. Preview accessibility includes both version labels and text values. Other size/Dynamic Type combinations were not exhaustively tested.
- Subagent correctness, architecture/UI, and security/impact reviews approved after fixing the pre-start cancellation race and preventing automatic-polishing pressure settings from cancelling a manually selected provider.

Observed model-quality limits remain: an early output changed a suggestion into a commitment, and another omitted secondary updates. Preservation instructions were strengthened, but semantic fidelity is not guaranteed by a prompt. The user must review the preview; Keep original and Undo remain available. No semantic-equivalence checker, measured battery savings, or live model-server deployment is claimed.

Reports/logs are ignored under .build, including integration-whisper-tiny-rewrite-apple.json, phone-whisper-tiny-rewrite-apple.json, rewrite-tests.log and rewrite-phone-*.log. Fixtures use isolated preferences/history/shared locations and generated audio. No credentials, device identifiers or model weights are committed.

## Recording screen awake, keyboard controls and rewrite goals (2026-10-25)

The recorder now acquires an idle-timer override only after recording successfully starts and restores the exact prior value on finish, cancel, interruption, native completion and failed startup. It does not alter the system's global Auto-Lock preference. A DEBUG check exercises the actual UIKit property for both prior Boolean values and repeated acquisition/release without accessing the microphone; generated fixtures report recordingScreenAwakePolicyVerified.

The final five goals are Default, Main point first, Tell a clear story, Professional message and Custom. Professional applies professional style only to that manual request. Custom retains its full existing directions budget. Goal/provider controls remain available with proposals and Rewrite again starts a fresh generation from the current unchanged original. Default instructions explicitly request recomposition beyond copy editing. Only manual rewrites use conservative variation (Apple unseeded random top-20/temperature 0.3, MLX/server 0.3); automatic grammar settings remain unchanged.

Whitespace-only/no-change proposals are labelled, cannot be accepted or create Undo, and can be retried. Existing previews remain isolated from transcript/history/clipboard/keyboard publication until explicit acceptance. Integration checks seed an unchanged proposal to verify non-publication, then exercise real generation and another explicit request from the preview before accept/Undo.

Validation:

- 58 root Swift, 45 mobile Swift and 15 Python tests passed (118 total). New cases include goal contracts, unchanged acceptance refusal/Undo retention, provider sampling separation, report rejection of false wake-state restoration and missing no-op/rerun guarantees. Tests were observed failing before the corresponding implementation changes.
- Simulator Debug, signed iPhone Debug and unsigned iPhone Release builds passed.
- Real Simulator Default, Tell a clear story and Professional message fixtures passed with actual rewritten output, wake-state restoration, no-op rejection, explicit rerun, preview isolation and accept/Undo. Reports are in .build/rewrite-v2-default.log, rewrite-v2-story.log and rewrite-v2-professional.log.
- Computer-use inspection confirmed all five picker entries and Rewrite again alongside goal/provider controls after a proposal. The real software keyboard was opened for Custom directions and the main transcript, then dismissed with the keyboard-down toolbar control. The main bottom menu returned. Models/Settings focus bindings/toolbars compile and were source-reviewed; their keyboard interaction was not separately completed.
- The signed update installed on the authorized iPhone. The final physical Professional-message fixture was blocked by iOS Locked before launch; no new physical model-inference or long microphone recording claim is made for this revision. Existing generated fixtures use no microphone or clipboard.
- Independent provider/resource, state/model and UI reviews approved the changes. No semantic equivalence guarantee, measured battery improvement, or automatic retry is claimed.

The model may still return unchanged or imperfect wording. In one Professional fixture, a working microphone was described as having completed testing; state/transport tests do not establish semantic equivalence. The app now reports no-change honestly and keeps review/retry/rejection available. Users should inspect the proposal before acceptance.

## Desktop/mobile repository layout (2026-10-25)

The apps now live in sibling desktop/ and mobile/ directories. The existing desktop Swift package exports WisprCore; both mobile packages reference ../../desktop and the Xcode project references ../desktop. Product names, bundle IDs, dependency versions, source behavior, runtime locations and app data remain unchanged.

Validation from the repository root passed:

- make test: 58 desktop/shared Swift tests, 25 desktop Python tests, 45 mobile Swift tests and 15 mobile Python tests (143 total).
- make desktop and make verify: macOS Release bundle build, ad hoc signature and bundled worker startup/closed-resource checks.
- make mobile: iOS Simulator Debug build.
- make mobile-device: unsigned native iPhone Release build.
- SHA-256 comparisons confirmed all 77 recorded application/script source files unchanged after relocation. Signing configuration bytes and all personal project signing fields match the pre-move snapshot.
- Path, architecture and impact/security reviews approved the reorganization. Public project defaults are committed; existing personal signing overrides remain local and unstaged.

Current build/reproduction commands use the new directories. Historical design and fixture reports retain their original as-of paths. Path-sensitive generated caches were retained under ignored mobile/.build/pre-reorganization backups and rebuilt; no model weights, signing credentials, user data, or generated bundles were added to Git. This change does not install or deploy either app.

## Reproduce

```sh
cd mobile
make test
make build
make device
python3 scripts/integration-transcription.py --model whisper-tiny
python3 scripts/integration-transcription.py --model parakeet-v3
```

The integration script generates speech rather than recording the microphone, never reads personal audio, and suppresses clipboard writes for the debug fixture run. Fixture runs use a separate UserDefaults suite and separate history, recordings, and shared-transcript locations; only reusable model weights are shared with normal runs. Reports and full build logs are stored in the ignored `.build/` directory. Dependencies and models require an initial download; no model weights or generated build products are committed.
