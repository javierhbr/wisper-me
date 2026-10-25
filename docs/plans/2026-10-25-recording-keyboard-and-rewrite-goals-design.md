# Recording visibility, keyboard dismissal and rewrite goals

The user requested screen-awake recording, a way to dismiss the keyboard and reach the bottom menu, repeatable manual rewriting, and goal presets. The final goals are Default, Main point first, Tell a clear story, Professional message and Custom.

The recorder captures the existing UIApplication idle-timer value only after native recording starts, disables automatic sleep during recording, and restores the captured value on every cleanup path. A DEBUG check exercises both prior values and idempotent restoration without using the microphone.

Text-entry screens use explicit focus state, a Hide keyboard toolbar action and interactive scroll dismissal. The rewrite sheet keeps goals/provider controls and a Rewrite again action available with proposals. Changing a goal invalidates an old draft without changing current text or publication.

Default asks for recomposition beyond grammar correction while preserving every factual claim, name, number, uncertainty, intention and requested action. Story does not invent chronology/causes/dialogue. Professional does not invent recipients or commitments and uses professional generation style without changing global style preferences. Custom retains the existing input budget. Every generation captures immutable goal/provider/text/direction/settings snapshots.

Unchanged proposals are detected after whitespace normalization, clearly marked, and cannot be accepted or create Undo. Another explicit request remains available from the same original. Only manual rewriting uses conservative unseeded sampling; grammar settings remain unchanged. No automatic retry is introduced.

Verification covers state/provider unit regressions, actual UIKit wake-state restoration, real generation/rerun from preview, injected unchanged acceptance rejection, publication isolation, accept/Undo, native builds and visual keyboard/goal tests. Models cannot guarantee a changed or semantically identical result, so preview and rejection remain necessary.
