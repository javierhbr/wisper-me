import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

class InstallerTests(unittest.TestCase):
    def test_cancellation_terminates_and_reaps_owned_child(self):
        module = Path(__file__).resolve().parents[1] / "runtime/install-runtime.py"
        with tempfile.TemporaryDirectory(prefix="wisprm-install-test-") as temporary:
            pidfile = Path(temporary) / "child.pid"
            child_code = "import os,time; from pathlib import Path; Path(" + repr(str(pidfile)) + ").write_text(str(os.getpid())); time.sleep(60)"
            parent_code = (
                "import importlib.util,signal; "
                "spec=importlib.util.spec_from_file_location('installer'," + repr(str(module)) + "); "
                "module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); "
                "runner=module.Runner(); signal.signal(signal.SIGTERM,runner.stop); "
                "runner.run([" + repr(sys.executable) + ",'-c'," + repr(child_code) + "])"
            )
            parent = subprocess.Popen([sys.executable, "-c", parent_code])
            child_pid = None
            try:
                deadline = time.monotonic() + 5
                while not pidfile.exists() and time.monotonic() < deadline:
                    time.sleep(0.02)
                self.assertTrue(pidfile.exists(), "Owned child must start")
                child_pid = int(pidfile.read_text())
                parent.terminate()
                self.assertEqual(parent.wait(timeout=10), 128 + signal.SIGTERM)
                with self.assertRaises(ProcessLookupError):
                    os.kill(child_pid, 0)
            finally:
                if parent.poll() is None:
                    parent.terminate()
                    parent.wait(timeout=10)
                if child_pid is not None:
                    try:
                        os.killpg(child_pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass

if __name__ == "__main__":
    unittest.main()
