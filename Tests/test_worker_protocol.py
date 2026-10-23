"""Protocol and model-reference tests without importing a speech model."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from contextlib import contextmanager
from types import SimpleNamespace, ModuleType
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runtime"))
from worker import model_reference, merge_text, Recognizer, download_snapshot

class WorkerProtocolTests(unittest.TestCase):
    def run_worker(self, requests):
        data = "".join(json.dumps(value) + "\n" for value in requests)
        result = subprocess.run([sys.executable, str(ROOT / "runtime/worker.py")], input=data,
                                text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [json.loads(line) for line in result.stdout.splitlines()]

    def test_owned_group_handshake_errors_and_shutdown(self):
        replies = self.run_worker([
            {"id": "1", "op": "ping"}, {"id": "2", "op": "transcribe", "audio": "/missing.wav"},
            {"id": "3", "op": "prepare", "engine": "Unknown", "model": "anything"},
            {"id": "4", "op": "quit"}])
        handshake = replies[0]
        self.assertEqual(handshake["event"], "ready")
        self.assertEqual(handshake["pid"], handshake["process_group"])
        replies = [value for value in replies if "event" not in value]
        self.assertEqual(len(replies), 3)
        self.assertTrue(replies[0]["ready"])
        self.assertFalse(replies[1]["ok"])
        self.assertIn("Load a speech model", replies[1]["error"])
        self.assertFalse(replies[2]["ok"])

    def test_malformed_request_does_not_terminate_worker(self):
        replies = self.run_worker([[], {"id": "still-alive", "op": "ping"}])
        self.assertFalse(replies[1]["ok"])
        self.assertEqual(replies[-1]["id"], "still-alive")
        self.assertTrue(replies[-1]["ok"])

    def test_eof_is_a_clean_shutdown(self):
        self.assertEqual(self.run_worker([])[0]["event"], "ready")

    def test_locked_presets_and_explicit_custom_revisions(self):
        with tempfile.TemporaryDirectory(prefix="wisprm-lock-test-") as directory:
            lock = Path(directory) / "models.lock.json"
            revision = "a" * 40
            lock.write_text(json.dumps({"models": {"mlx-community/whisper-tiny": {"revision": revision}}}))
            self.assertEqual(model_reference("mlx-community/whisper-tiny", lock),
                             ("mlx-community/whisper-tiny", revision, False))
            with self.assertRaises(ValueError):
                model_reference("mlx-community/whisper-tiny@" + "b" * 40, lock)
            with self.assertRaises(ValueError):
                model_reference("mlx-community/whisper-base-mlx", lock)
            self.assertEqual(model_reference("custom/recognizer@" + revision, lock),
                             ("custom/recognizer", revision, False))
            with self.assertRaises(ValueError):
                model_reference("custom/recognizer@main", lock)

    def test_parakeet_receives_bounded_private_chunks_and_preserves_model(self):
        @contextmanager
        def chunks(*args, **kwargs):
            yield iter([bytes(29 * 16000 * 4), bytes(29 * 16000 * 4)])
        with tempfile.TemporaryDirectory(prefix="wisprm-worker-chunks-") as directory:
            recognizer = Recognizer(chunk_directory=directory)
            paths = []
            class FakeModel:
                def transcribe(self, value):
                    path = Path(value); paths.append(path)
                    self_test.assertEqual(path.stat().st_mode & 0o777, 0o600)
                    with wave.open(str(path), "rb") as audio:
                        self_test.assertLessEqual(audio.getnframes(), 30 * 16000)
                    return SimpleNamespace(text="window " + str(len(paths)))
            self_test = self
            model = FakeModel(); recognizer.model = model; recognizer.engine = "Parakeet"
            with patch("worker.decode_audio_chunks", chunks):
                result = recognizer.transcribe("unused.wav", "en")
            self.assertEqual(result["language"], "en")
            self.assertEqual(result["text"], "window 1 window 2")
            self.assertIs(recognizer.model, model)
            self.assertEqual(len(paths), 2)
            self.assertTrue(all(not path.exists() for path in paths))

    def test_pinned_cache_is_offline_and_only_cache_misses_download(self):
        class CacheMiss(Exception):
            pass
        hub = ModuleType("huggingface_hub")
        errors = ModuleType("huggingface_hub.errors")
        errors.LocalEntryNotFoundError = CacheMiss
        with tempfile.TemporaryDirectory(prefix="wisprm-cached-model-") as directory:
            root = Path(directory)
            (root / "config.json").write_text("{}")
            (root / "weights.npz").write_bytes(b"test weights")
            calls = []
            def cached(**options):
                calls.append(options)
                return directory
            hub.snapshot_download = cached
            with patch.dict(sys.modules, {"huggingface_hub": hub, "huggingface_hub.errors": errors}):
                self.assertEqual(download_snapshot("custom/model", "a" * 40, "Whisper"), directory)
                self.assertEqual(len(calls), 1)
                self.assertTrue(calls[0]["local_files_only"])
                calls.clear()
                def missing(**options):
                    calls.append(options)
                    if options.get("local_files_only"):
                        raise CacheMiss("not cached")
                    return directory
                hub.snapshot_download = missing
                self.assertEqual(download_snapshot("custom/model", "a" * 40, "Whisper"), directory)
                self.assertEqual(len(calls), 2)
                self.assertEqual(calls[1]["revision"], "a" * 40)
                def denied(**options):
                    raise PermissionError("not a cache miss")
                hub.snapshot_download = denied
                with self.assertRaises(PermissionError):
                    download_snapshot("custom/model", "a" * 40, "Whisper")

    def test_only_multiword_overlap_is_merged(self):
        self.assertEqual(merge_text("Send the meeting notes", "meeting notes tomorrow."),
                         "Send the meeting notes tomorrow.")
        self.assertEqual(merge_text("Very", "very good"), "Very very good")

if __name__ == "__main__":
    unittest.main()
