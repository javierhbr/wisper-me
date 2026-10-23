"""Bounded audio decoding and temp-file cleanup without importing ML models."""
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import wave

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "runtime"))
from audio_pipeline import (AudioLimits, AudioDecodeError, AudioLimitError, decode_audio_chunks,
                            pcm_wave_file, validate_audio_file)

class AudioPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wisprm-audio-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.audio = self.root / "sample.wav"
        with wave.open(str(self.audio), "wb") as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(16000)
            output.writeframes(bytes(16000 * 2))

    def fake_decoder(self, seconds=1, exit_code=0):
        code = ("import sys; sys.stdout.buffer.write(bytes(" + str(int(seconds * 16000 * 4)) +
                ")); sys.stdout.buffer.flush(); raise SystemExit(" + str(exit_code) + ")")
        return [sys.executable, "-c", code]

    def test_rejects_oversized_and_non_audio_input_before_decoder(self):
        huge = self.root / "huge.wav"
        with huge.open("wb") as handle:
            handle.write(b"RIFF" + bytes(4) + b"WAVE")
            handle.truncate(100 * 1024 * 1024 + 1)
        with self.assertRaises(AudioLimitError):
            validate_audio_file(huge)
        invalid = self.root / "pretend.wav"; invalid.write_text("not audio")
        with self.assertRaises(AudioDecodeError):
            validate_audio_file(invalid)

    def test_standard_container_signatures_and_extensions(self):
        signatures = {
            ".caf": b"caff" + bytes(12), ".aiff": b"FORM" + bytes(4) + b"AIFF",
            ".aif": b"FORM" + bytes(4) + b"AIFC", ".m4a": bytes(4) + b"ftypM4A ",
            ".mp3": b"ID3" + bytes(16), ".flac": b"fLaC" + bytes(16),
            ".ogg": b"OggS" + bytes(16), ".opus": b"OggS" + bytes(16),
            ".webm": b"\x1a\x45\xdf\xa3" + bytes(16)}
        for extension, content in signatures.items():
            path = self.root / ("sample" + extension); path.write_bytes(content)
            self.assertEqual(validate_audio_file(path), path.resolve())

    def test_streams_in_bounded_windows(self):
        with decode_audio_chunks(self.audio, ffmpeg_command=self.fake_decoder(seconds=65)) as chunks:
            lengths = [len(chunk) for chunk in chunks]
        self.assertEqual(sum(lengths), 65 * 16000 * 4)
        self.assertEqual(len(lengths), 3)
        self.assertTrue(all(length <= 30 * 16000 * 4 for length in lengths))

    def test_rejects_excess_decoded_duration(self):
        limits = AudioLimits(max_duration_seconds=1, chunk_seconds=0.25)
        with self.assertRaises(AudioLimitError):
            with decode_audio_chunks(self.audio, ffmpeg_command=self.fake_decoder(seconds=2), limits=limits) as chunks:
                list(chunks)

    def test_decoder_failure_is_not_successful_empty_transcription(self):
        with self.assertRaises(AudioDecodeError):
            with decode_audio_chunks(self.audio, ffmpeg_command=self.fake_decoder(seconds=0, exit_code=1)) as chunks:
                list(chunks)

    def test_timeout_and_consumer_cancellation_reap_decoder(self):
        real_popen = subprocess.Popen
        children = []
        def spawn(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            children.append(child)
            return child
        with patch("audio_pipeline.subprocess.Popen", side_effect=spawn):
            with self.assertRaises(AudioDecodeError):
                with decode_audio_chunks(self.audio,
                    ffmpeg_command=[sys.executable, "-c", "import time; time.sleep(10)"],
                    limits=AudioLimits(read_timeout_seconds=0.1)) as chunks:
                    list(chunks)
            self.assertIsNotNone(children[-1].poll())
            with self.assertRaises(SystemExit):
                with decode_audio_chunks(self.audio,
                    ffmpeg_command=[sys.executable, "-c",
                        "import os\nwhile True:\n os.write(1,bytes(65536))"],
                    limits=AudioLimits(chunk_seconds=0.1)) as chunks:
                    next(chunks)
                    raise SystemExit(143)
            self.assertIsNotNone(children[-1].poll())

    def test_temporary_wave_is_owner_only_and_deleted_on_error(self):
        created = None
        with self.assertRaises(RuntimeError):
            with pcm_wave_file(struct.pack("<4f", 0.0, 0.25, -0.25, 1.0), directory=self.root) as path:
                created = path
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                with wave.open(str(path), "rb") as audio:
                    self.assertEqual(audio.getnchannels(), 1)
                    self.assertEqual(audio.getframerate(), 16000)
                    self.assertEqual(audio.getnframes(), 4)
                raise RuntimeError("cancelled model")
        self.assertFalse(created.exists())

if __name__ == "__main__":
    unittest.main()
