#!/usr/bin/env python3
"""Isolated runtime setup with owned child-process groups and cancellation cleanup."""
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys

class Runner:
    def __init__(self):
        self.active = None

    def stop(self, signum, frame):
        # Unwind subprocess.wait before cleanup: wait's internal lock is not reentrant.
        raise SystemExit(128 + signum)

    def run(self, command):
        child = subprocess.Popen(command, start_new_session=True)
        self.active = child
        try:
            code = child.wait()
            if code:
                raise SystemExit(code)
        except BaseException:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=8)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait()
            raise
        finally:
            self.active = None

def main():
    if platform.machine() != "arm64" or sys.version_info < (3, 10):
        raise SystemExit("Apple Silicon and Python 3.10+ are required.")
    target = Path(sys.argv[1]).expanduser().resolve()
    source = Path(__file__).resolve().parent
    runner = Runner()
    signal.signal(signal.SIGTERM, runner.stop)
    signal.signal(signal.SIGINT, runner.stop)
    runner.run([sys.executable, "-m", "venv", str(target)])
    python = str(target / "bin/python3")
    runner.run([python, "-m", "pip", "install", "--disable-pip-version-check", "--upgrade", "pip"])
    runner.run([python, "-m", "pip", "install", "--disable-pip-version-check", "-r", str(source / "requirements.txt")])
    runner.run([python, "-c",
                'import imageio_ffmpeg,pathlib,sys; p=pathlib.Path(sys.executable).parent/"ffmpeg"; '
                'p.unlink(missing_ok=True); p.symlink_to(imageio_ffmpeg.get_ffmpeg_exe()); '
                'import mlx_whisper,parakeet_mlx'])
    (target / ".wisprm-ready").touch()
    print("wisprM local runtime is ready.", flush=True)

if __name__ == "__main__":
    main()
