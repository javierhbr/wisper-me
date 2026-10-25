"""Real MLX inference against locally synthesized speech, no microphone required."""
import argparse
import json
import os
import re
import signal
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--engine", choices=["Whisper", "Parakeet"], required=True)
parser.add_argument("--model", required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
runtime = Path.home() / "Library/Application Support/wisprM/runtime"
started = time.monotonic()
with tempfile.TemporaryDirectory(prefix="wisprm-inference-") as temporary:
    audio = Path(temporary) / "speech.aiff"
    expected = "Hello, this is a real local transcription test. Please send the meeting notes tomorrow morning."
    subprocess.run(["/usr/bin/say", "-o", str(audio), expected], check=True, timeout=30)
    requests = [
        {"id": "prepare", "op": "prepare", "engine": args.engine, "model": args.model},
        {"id": "transcribe", "op": "transcribe", "audio": str(audio), "language": "en"},
        {"id": "quit", "op": "quit"},
    ]
    environment = os.environ.copy()
    environment["WISPRM_RECORDINGS_DIR"] = str(Path(temporary) / "Recordings")
    environment["HF_HUB_OFFLINE"] = "1"
    worker = subprocess.Popen(
        [str(runtime / "bin/python3"), str(root / "runtime/worker.py")],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env=environment, start_new_session=True)
    try:
        stdout, stderr = worker.communicate("".join(json.dumps(r) + "\n" for r in requests), timeout=1500)
    finally:
        if worker.poll() is None:
            os.killpg(worker.pid, signal.SIGTERM)
            try:
                worker.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(worker.pid, signal.SIGKILL)
                worker.wait()
    result = subprocess.CompletedProcess(worker.args, worker.returncode, stdout, stderr)
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    terminal = {r["id"]: r for r in replies if "ok" in r}
    print(json.dumps(replies, indent=2))
    if result.returncode or not terminal.get("prepare", {}).get("ok") or not terminal.get("transcribe", {}).get("ok"):
        print(result.stderr[-5000:])
        raise SystemExit("Real inference failed")
    text = terminal["transcribe"]["text"]
    # A real ASR test measures word error rate rather than requiring verbatim decoding.
    reference = re.findall(r"\w+", expected.lower())
    hypothesis = re.findall(r"\w+", text.lower())
    row = list(range(len(hypothesis) + 1))
    for i, word in enumerate(reference, 1):
        next_row = [i]
        for j, candidate in enumerate(hypothesis, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j-1] + (word != candidate)))
        row = next_row
    wer = row[-1] / len(reference)
    assert wer <= 0.25, f"Word error rate {wer:.1%}: {text}"
    report = {"engine": args.engine, "model": args.model, "expected": expected, "actual": text, "word_error_rate": round(wer, 4),
              "elapsed_including_download_seconds": round(time.monotonic()-started, 2), "passed": True}
    output = root / "verification"
    output.mkdir(exist_ok=True)
    (output / ("transcription-" + args.engine.lower() + ".json")).write_text(json.dumps(report, indent=2))
    print("PASS", args.engine, report["elapsed_including_download_seconds"], "seconds")
