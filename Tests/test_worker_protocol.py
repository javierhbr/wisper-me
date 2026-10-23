"""Protocol tests use no model or mic; successful inference is not mocked."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

class WorkerProtocolTests(unittest.TestCase):
    def test_ping_errors_and_shutdown(self):
        worker = Path(__file__).resolve().parents[1] / "runtime" / "worker.py"
        data = "\n".join(json.dumps(r) for r in [
            {"id": "1", "op": "ping"},
            {"id": "2", "op": "transcribe", "audio": "/missing.wav"},
            {"id": "3", "op": "prepare", "engine": "Unknown", "model": "anything"},
            {"id": "4", "op": "quit"}]) + "\n"
        result = subprocess.run([sys.executable, str(worker)], input=data, text=True,
                                capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0)
        replies = [r for line in result.stdout.splitlines() if "event" not in (r := json.loads(line))]
        self.assertEqual(len(replies), 3)
        self.assertTrue(replies[0]["ready"])
        self.assertFalse(replies[1]["ok"])
        self.assertIn("Load a speech model", replies[1]["error"])
        self.assertFalse(replies[2]["ok"])
if __name__ == "__main__":
    unittest.main()
