# Apple Intelligence transcript polishing

Add an optional Apple Intelligence provider to the iPhone app's existing text-polishing picker. Keep existing saved preferences and the default of local cleanup only. Whisper and Parakeet continue to recognize speech; Apple's on-device system model receives only the completed transcript. The Mac app is outside this change.

Use Foundation Models on iOS 26 and later. Show device eligibility, Apple Intelligence enablement, model readiness, and selected-language support in Models. Refresh availability when the app returns to the foreground and check again for each request. No third-party packages, cloud model, or app-managed weight download is needed for this provider.

Create a fresh LanguageModelSession per transcript with copy-editing instructions that preserve language, meaning, names, numbers, and formatting. Request structured output containing only the edited text. Bound input size and leave response token limits at their framework defaults to avoid deliberately truncating text. Reuse output validation. Context, availability, guardrail, and generation errors preserve deterministic cleanup and show an explanatory message. Never silently switch providers.

Capture provider consent when recording begins, recheck it before accepting results, and cancel polishing if the user changes providers or the app leaves the foreground. Unload app-managed inference weights before the system-model request to reduce memory use. Clipboard and keyboard publishing retain their existing behavior.

Validate consent changes with host unit tests, compile for device and Simulator, and exercise the real provider through the Debug-only generated-speech route. If a physical phone or Apple Intelligence is unavailable, report the exact limit rather than claiming a successful model run.

References: [availability and sessions](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), [language support](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models), [generation limits](https://developer.apple.com/documentation/foundationmodels/generationoptions).
