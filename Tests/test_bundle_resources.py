import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

class BundleResourceTests(unittest.TestCase):
    def test_worker_startup_does_not_write_into_its_source_directory(self):
        source = Path(__file__).resolve().parents[1] / "runtime"
        with tempfile.TemporaryDirectory(prefix="wisprm-resource-test-") as temporary:
            target = Path(temporary)
            for name in ["worker.py", "audio_pipeline.py"]:
                shutil.copy2(source / name, target / name)
            request = json.dumps({"id": "check", "op": "ping"}) + "\n" + json.dumps({"op": "quit"}) + "\n"
            result = subprocess.run([sys.executable, str(target / "worker.py")], input=request, text=True,
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            replies = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertTrue(any(r.get("id") == "check" and r.get("ok") for r in replies))
            self.assertFalse((target / "__pycache__").exists(), "Worker imports must not mutate a sealed app bundle")
if __name__ == "__main__":
    unittest.main()
