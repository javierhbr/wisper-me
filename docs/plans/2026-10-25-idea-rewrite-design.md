# On-demand idea rewriting

After dictation, the user can choose Rewrite idea to reorganize the explanation, improve flow, and remove repetition while preserving material facts, names, numbers, uncertainty, language, and speaker intent. Optional directions can request an emphasis or structure. It never runs automatically and remains available when automatic grammar polishing is off.

A sheet selects Apple Intelligence, the configured local MLX model, or the configured model server. Defaults follow the existing provider when enabled, otherwise Apple Intelligence. Server use is disclosed before the user requests generation; there is no fallback to another provider.

Generation captures immutable text, settings, provider and directions. A separate state object keeps the original and proposal, rejects cancelled or superseded responses, and invalidates drafts after text/settings changes. Closing, cancelling, or rejecting leaves current text, clipboard, history and keyboard publication unchanged. The preview switches between Original and Rewrite. Use rewrite accepts and delivers text using the existing copy/history/keyboard policy; one-level Undo restores exact source text and removes the accepted revision's history entry. Editing after acceptance invalidates Undo.

Providers share explicit rewrite instructions and JSON-separated source/directions. Grammar correction keeps its existing prompts. Existing context/output bounds remain, with a 2000-byte directions limit; overlong requests fail without truncation or silent summarization. Apple/local jobs cancel when the app becomes inactive or pressure policy requires it. Local MLX retains sequential memory ownership.

Verification covers pure state transitions including cancellation/retries/ABA, provider request/output guards, Simulator inference with automatic polishing off, and real preview/accept/undo delivery through isolated generated fixtures. Hardware and UI checks are recorded separately from measured language quality and energy performance.
