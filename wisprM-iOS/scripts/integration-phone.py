#!/usr/bin/env python3
"""Run generated-speech transcription in an installed Debug app on an iPhone.

Uses only this app's fixture and report in Documents, never the microphone.
Keep the phone unlocked and the app in the foreground during inference.
"""
import argparse
import json
import plistlib
from pathlib import Path
import subprocess
import time


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="CoreDevice identifier or phone name")
    parser.add_argument("--model", choices=["whisper-tiny", "whisper-base", "whisper-small", "parakeet-v3"], default="whisper-tiny")
    parser.add_argument("--polish-model")
    parser.add_argument("--app", type=Path, default=root / ".build/Phone/Build/Products/Debug-iphoneos/wisprM.app")
    args = parser.parse_args()
    with (args.app / "Info.plist").open("rb") as file:
        bundle = plistlib.load(file)["CFBundleIdentifier"]
    build = root / ".build"
    build.mkdir(exist_ok=True)
    fixture = build / "phone-generated-speech.caf"
    report = build / ("phone-" + args.model + ("-polished" if args.polish_model else "") + ".json")
    report.write_text("{}\n")

    def command(*arguments, check=True):
        return subprocess.run(list(arguments), check=check, capture_output=True, text=True, timeout=45)

    def device(*arguments, check=True):
        return command("xcrun", "devicectl", "device", *arguments,
                       "--device", args.device, "--timeout", "30", check=check)

    def copy(direction, source, destination, check=True):
        return device("copy", direction, "--domain-type", "appDataContainer",
                      "--domain-identifier", bundle, "--source", str(source),
                      "--destination", str(destination), check=check)

    command("/usr/bin/say", "-o", str(fixture), "The quick brown fox jumps over the lazy dog.")
    copy("to", fixture, "Documents/integration-fixture.caf")
    # Clear the old report so a previous test cannot count as this test's result.
    copy("to", report, "Documents/integration-result.json")
    arguments = ["xcrun", "devicectl", "device", "process", "launch", "--device", args.device,
                 "--timeout", "30", "--terminate-existing", bundle,
                 "--integration-audio", "integration-fixture.caf", "--integration-model", args.model]
    if args.polish_model:
        arguments += ["--integration-polish-model", args.polish_model]
    command(*arguments)
    print("Waiting for real iPhone model download/load and transcription…", flush=True)
    deadline = time.monotonic() + 1200
    while time.monotonic() < deadline:
        transfer = copy("from", "Documents/integration-result.json", report, check=False)
        if transfer.returncode == 0:
            try:
                result = json.loads(report.read_text())
            except (ValueError, OSError):
                result = {}
            if result.get("model") == args.model:
                print(json.dumps(result, indent=2, ensure_ascii=False), flush=True)
                if result.get("error") or not result.get("text", "").strip():
                    raise SystemExit("Physical-phone inference failed; see the report above.")
                print("Real iPhone transcription passed.", flush=True)
                return
        time.sleep(3)
    raise SystemExit("Timed out. Keep the phone unlocked with wisprM in the foreground and inspect the app.")


if __name__ == "__main__":
    main()
