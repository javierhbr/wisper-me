#!/usr/bin/env python3
"""Verify saved speech selection and cache-only loading across real app processes.

Uses the isolated Debug integration preferences. No microphone or clipboard access.
The first phase prepares a model; later phases must restore it without downloads.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import time
from simulator import choose


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator")
    parser.add_argument("--model", choices=["whisper-tiny", "parakeet-v3"], default="parakeet-v3")
    args = parser.parse_args()
    simulator = choose(args.simulator)["udid"]
    app = root / ".build/DerivedData/Build/Products/Debug-iphonesimulator/wisprM.app"
    with (app / "Info.plist").open("rb") as file:
        bundle = plistlib.load(file)["CFBundleIdentifier"]
    # The production preparation/transcription path saves the choice and its receipt.
    subprocess.run([sys.executable, str(root / "scripts/integration-transcription.py"),
                    "--simulator", simulator, "--model", args.model], check=True)

    def command(*arguments, check=True):
        return subprocess.run(list(arguments), check=check, capture_output=True, text=True, timeout=30)

    container = Path(command("xcrun", "simctl", "get_app_container", simulator, bundle, "data").stdout.strip())
    models = container / "Library/Application Support/wisprM/Models"

    def weights():
        # Compare metadata rather than reading hundreds of MB of unchanged weights.
        return sorted((str(path.relative_to(models)), path.stat().st_size, path.stat().st_mtime_ns)
                      for path in models.rglob("*") if path.is_file() and path.stat().st_size >= 1_000_000)

    before = weights()
    assert before, "No model weights were prepared."
    report = container / "Documents/integration-restore.json"
    def startup_report(*extra):
        report.unlink(missing_ok=True)
        arguments = ["xcrun", "simctl", "launch", "--terminate-running-process", simulator, bundle,
                     "--integration-restore-check", *extra]
        try:
            command(*arguments)
            deadline = time.monotonic() + 120
            while not report.is_file() and time.monotonic() < deadline:
                time.sleep(1)
            if not report.is_file():
                raise SystemExit("The app did not complete its automatic startup restoration.")
            return json.loads(report.read_text())
        finally:
            command("xcrun", "simctl", "terminate", simulator, bundle, check=False)

    reports = []
    for forget_receipts in (False, True):
        flags = ["--integration-forget-receipts"] if forget_receipts else []
        result = startup_report(*flags)
        print(json.dumps(result, indent=2), flush=True)
        assert result["selectedModel"] == args.model, "Saved selection changed on restart."
        assert result["loadedModel"] == args.model and result["ready"] and result["canDictate"], "The selected model did not become ready."
        assert result["downloadAllowed"] is False, "Startup must not permit a model download."
        assert not result["error"], result["error"]
        assert result["speechPreparationCount"] == 1, "A startup must not repeatedly prepare the engine."
        assert result["modelStorageScanCount"] == int(forget_receipts), "Cached receipts must avoid storage rescans; recovery measures once."
        assert weights() == before, "Cached model weights changed during restoration."
        reports.append(dict(result, receiptsRecovered=forget_receipts))

    lifecycle = startup_report("--integration-lifecycle-check")
    print(json.dumps(lifecycle, indent=2), flush=True)
    assert lifecycle["selectedModel"] == args.model and lifecycle["canDictate"], "Lifecycle policy lost the cached selection."
    for key in ("foregroundPreparationDelta", "historyPreparationDelta", "settingsPreparationDelta"):
        assert lifecycle[key] == 0, f"Unnecessary speculative model work: {key}"
    assert weights() == before, "Lifecycle checks changed cached model weights."
    (root / ".build" / ("lifecycle-" + args.model + ".json")).write_text(json.dumps(lifecycle, indent=2) + "\n")
    archive = root / ".build" / ("relaunch-" + args.model + ".json")
    archive.write_text(json.dumps(reports, indent=2) + "\n")
    print("Saved selection, cache-only startup, receipt reuse/recovery, and lifecycle preload policy passed.", flush=True)


if __name__ == "__main__":
    main()
