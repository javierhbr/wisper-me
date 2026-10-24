#!/usr/bin/env python3
"""Run actual on-device-library transcription inside the iOS simulator.

Uses generated speech, no microphone or personal files. The app's debug-only
fixture route skips clipboard writes and uses its normal production pipeline.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time
from simulator import choose, install

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("--simulator")
parser.add_argument("--model", choices=["whisper-tiny", "whisper-base", "whisper-small", "parakeet-v3"], default="whisper-tiny")
polishing = parser.add_mutually_exclusive_group()
polishing.add_argument("--polish-model")
polishing.add_argument("--apple-intelligence", action="store_true")
parser.add_argument("--phrase", default="The quick brown fox jumps over the lazy dog.")
parser.add_argument("--language", default="auto")
args = parser.parse_args()
app = root / ".build/DerivedData/Build/Products/Debug-iphonesimulator/wisprM.app"
if not app.is_dir(): raise SystemExit("Run make build first.")
def run(*arguments, **options): return subprocess.run(list(arguments), check=True, text=True, **options)
device = choose(args.simulator)
args.simulator = device["udid"]
bundle = install(device)
container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", args.simulator, bundle, "data"], text=True).strip())
documents = container / "Documents"; documents.mkdir(exist_ok=True)
audio = documents / "integration-fixture.caf"
report = documents / "integration-result.json"
report.unlink(missing_ok=True)
fixture = root / ".build/generated-speech.caf"
run("/usr/bin/say", "-o", str(fixture), args.phrase)
shutil.copyfile(fixture, audio)
subprocess.run(["xcrun", "simctl", "terminate", args.simulator, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
console = (root / ".build" / ("integration-" + args.model + "-console.log")).open("w")
launcher = None
try:
    arguments = ["xcrun", "simctl", "launch", "--console", args.simulator, bundle, "--integration-audio", str(audio), "--integration-model", args.model]
    if args.polish_model: arguments += ["--integration-polish-model", args.polish_model]
    if args.apple_intelligence: arguments += ["--integration-apple-intelligence"]
    arguments += ["--integration-language", args.language]
    launcher = subprocess.Popen(arguments, stdout=console, stderr=subprocess.STDOUT)
    print("Waiting for the real model download/load and transcription…", flush=True)
    deadline = time.monotonic() + 1200
    while time.monotonic() < deadline:
        if report.is_file():
            result = json.loads(report.read_text())
            print(json.dumps(result, indent=2, ensure_ascii=False))
            suffix = "-apple-intelligence" if args.apple_intelligence else "-polished" if args.polish_model else ""
            archive = root / ".build" / ("integration-" + args.model + suffix + ".json")
            archive.write_text(json.dumps(result, indent=2) + "\n")
            if result.get("error") or not result.get("text", "").strip(): raise SystemExit(1)
            if (args.apple_intelligence or args.polish_model) and not result.get("polishingCompleted"): raise SystemExit(1)
            print("Real transcription passed.")
            break
        time.sleep(1)
        if launcher.poll() is not None and not report.exists(): raise SystemExit("The simulator app exited before producing a report. Inspect the integration console log.")
    else: raise SystemExit("Timed out. Inspect the simulator app and its logs.")
finally:
    try:
        subprocess.run(["xcrun", "simctl", "terminate", args.simulator, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
    finally:
        try:
            if launcher:
                try: launcher.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    launcher.terminate()
                    try: launcher.wait(timeout=5)
                    except subprocess.TimeoutExpired: launcher.kill(); launcher.wait(timeout=5)
        finally:
            console.close(); audio.unlink(missing_ok=True)
