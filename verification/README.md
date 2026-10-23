# Verification — review fixes, version 0.1.1

Verified on Apple Silicon with macOS26.6.2 and Swift6.3.2.

## Automated checks

- **51 Swift tests:** native lifecycle/audio, Core HTTP and privacy policies, workflow cancellation/cleanup, storage, migration, and formatting.
- **25 Python checks:** bounded decoding, private temporary audio, worker protocol/model pins/cache-first loading, installer process cleanup, and local app-installation safeguards.
- Actual cached **Whisper Tiny** and **Parakeet0.6B v3** inference against generated speech, with HF_HUB_OFFLINE=1. No model downloads. The short sample retained WER0.1333 for Whisper and0.0 for Parakeet; this is a functional check, not an accuracy/latency benchmark.
- Fully hashed dependency lock dry-run against the existing verified runtime. All62 packages were resolved from official package metadata; four default model revisions are immutable.
- Release app compilation and ad hoc code-signature verification after bundled-worker startup. Bytecode writes inside the app are disabled and regression-tested.
- Makefile build/test/verify targets passed. The actual install target was verified in an isolated Applications directory containing spaces; copied signatures and binary identity matched, and no staging files remained.
- Nine local-installer regressions cover updates, unrelated/running app protection, staging verification, rollback/retained backups, symlinks and safe build-output cleanup.
- Bounded HTTP text client previously checked against local Qwen2.5 1.5B; the final client is also checked again during release validation.

Tests use isolated HOME/TMPDIR/recording paths and fixture processes. Workflow checks inject a synthetic clipboard sink and empty credential provider; they never record audio, alter the real clipboard, or read user credentials.

## Review findings and fixes

| Finding | Fix and regression evidence |
| --- | --- |
| Credentials follow endpoint changes | Keychain account is normalized origin; old unscoped account never read. Origin normalization and cross-server separation tested. |
| Privacy-off ignored during capture | Live consent overrides captured settings, remains available while the runtime is busy, and cancels pending HTTP. Four workflow tests cover off before/after recognition, cancellation, and quit. |
| Global Paste destination race | Removed all global key/Paste synthesis. Only verified direct AX insertion remains; unknown/secure fields fail closed. Eligibility policy tested; native OS compatibility remains a manual check. |
| Unbounded imported audio |100MiB/600s limits, streamed PCM, <=30s inference windows. Decoder budget/signature/chunk tests plus actual offline inference. Picker offers only the worker's supported containers. |
| Shared cancellation handle | Independent capture/dictation/discovery/setup/polish tasks; discovery disabled during active work. Pending HTTP cancellation workflow test. |
| Worker descendants outlive cancellation | Verified owned group, TERM→grace→KILL, awaited direct child, restart serialization. Native fixture tests include decoder descendants and uncooperative workers. |
| Audio survives normal quit | Explicit owned-file registry, terminateLater/await cleanup, visible failures. Workflow and storage tests, including inaccessible-vs-missing paths. |
| URLSession retention | One owned bounded client, explicit invalidation and no delegate owner cycle. Cancellation/shutdown/reuse tests and source re-review. |
| Formatter corrupts names/URLs/ordinary words | Protected spans and mixed-case names; explicit spoken-command opt-in. Actual corruption regressions covered. |
| Unbounded HTTP responses | Receive-byte and Content-Length limits before JSON decode; bounded generation/resource time; no redirects. Chunked/open response fixtures verify early rejection. |
| Channel-zero-only eligibility | Multi-channel/interleaved RMS and frame budget tests. |
| MP3/FLAC picker mismatch | Native format policy and worker allowlists aligned; format, size and container-signature tests. |
| Unterminated reasoning reaches output | Strict stop reason, tool/refusal rejection, and complete reasoning-tag parsing. Malformed/truncated output tests. |
| Sticky original view / disabled Copy | Reset on transcript generation, visible return control while selected, display/copy based on the selected text. Native UI checked during packaging. |
| Silent history deletion failure | Delete directly; only ENOENT counts as absent. Preserve ownership/state and surface failures. Missing/inaccessible/deletion tests. |
| Meter updates, drifting deadline, sleeping watchdogs | Isolated meter view/polling; monotonic+frame deadline; canceled completed watchdogs. Lifecycle/audio tests. |
| Mutable dependencies/model defaults |62 exact package versions with1194 verified wheel hashes; four pinned model revisions. No unpinned pip upgrade. |

The first HTTP fixture run stalled because unfinished synthetic responses omitted MIME/version metadata. Corrected HTTP/1.1 application/json fixtures now exercise the original early-error assertions; no safety assertions were relaxed.

## Remaining validation limits

- No claim of universal AX insertion support. Unknown or unsupported fields deliberately require manual Command–V. No runtime permission was granted by these fixes.
- Generated PCM/buffer tests cover multi-channel behavior; the rebuilt capture path has not been exercised on every physical microphone/interface.
- The resource limits were tested with bounded fixtures; no intentional machine-exhaustion test or broad latency/RAM benchmark was performed.
- Arbitrary custom model weights and arbitrary compatible text servers are not certified.
- Launch-at-login across reboot, Intel Macs, App Store/Developer ID signing, and notarization remain unverified.
- An ad hoc rebuild can require the user to reauthorize macOS permissions.

Source code and public dependencies remain original/separate from Wispr Flow. The existing untracked .serena tooling folder was not modified.
