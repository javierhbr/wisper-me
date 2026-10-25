# Ten-minute iPhone recording with a warning

The user requested recordings up to ten minutes and an audible warning at nine minutes thirty seconds. Recordings still finish immediately when the user taps Finish, cancels, or receives an audio interruption.

A shared RecordingLimits value sets the recorder and audio decoder to 600 seconds. The warning starts at 570 seconds. The app bundles an original 0.55-second two-tone PCM chime in its existing asset catalogue and schedules AVAudioPlayer on the audio device clock when recording begins. Hidden waveform metering does not affect the scheduled warning. Every recorder cleanup path, including failed startup, stops and releases the player.

The chime follows the current playback route and media volume. The app does not force a different route or volume for the warning. No periodic timer or background assertion is added for it.

Validation includes a generated-audio decoder boundary test accepting 600 seconds and rejecting 601 seconds, Simulator and signed iPhone builds, resource inspection, and source review of cancellation and completion ownership. A full microphone recording through 9:30, hardware audibility, and ten-minute recognition performance require separate physical-device checks. Generated inference fixtures do not record the microphone.
