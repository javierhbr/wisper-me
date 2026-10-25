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
import sys
import tempfile
import time
from phone_fixture import launched_process, stop_owned_process, validate_transcription


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="CoreDevice identifier or phone name")
    parser.add_argument("--model", choices=["whisper-tiny", "whisper-base", "whisper-small", "parakeet-v3"], default="whisper-tiny")
    polishing = parser.add_mutually_exclusive_group()
    polishing.add_argument("--polish-model")
    polishing.add_argument("--apple-intelligence", action="store_true")
    parser.add_argument("--phrase", default=None)
    parser.add_argument("--language", default="auto")
    parser.add_argument("--cache-text-model", help="Cache an MLX model without loading it or discarding speech")
    parser.add_argument("--expect-apple-unavailable", action="store_true")
    parser.add_argument("--rewrite", action="store_true", help="Exercise manual rewrite preview, acceptance, and Undo")
    parser.add_argument("--rewrite-directions", default="", help="Optional instructions for the idea rewrite")
    parser.add_argument("--rewrite-provider", choices=["apple", "local"], default="apple")
    parser.add_argument("--rewrite-goal", choices=["default", "main-point-first", "clear-story", "professional", "custom"], help="Goal preset; defaults to Custom with directions, otherwise Default")
    parser.add_argument("--app", type=Path, default=root / ".build/Phone/Build/Products/Debug-iphoneos/wisprM.app")
    args = parser.parse_args()
    if args.phrase is None:
        args.phrase = ("The microphone works now. We still have keyboard testing left. We should tell the team today. I think we should delay the release until Friday because the keyboard is not fully tested."
                       if args.rewrite else "The quick brown fox jumps over the lazy dog.")
    if args.rewrite_goal is not None and not args.rewrite:
        parser.error("--rewrite-goal requires --rewrite")
    args.rewrite_goal = args.rewrite_goal or ("custom" if args.rewrite_directions.strip() else "default")
    if args.rewrite and args.rewrite_goal == "custom" and not args.rewrite_directions.strip():
        parser.error("Custom rewrite goal requires --rewrite-directions")
    if args.rewrite_directions and args.rewrite_goal != "custom":
        parser.error("--rewrite-directions requires the Custom goal")
    if args.rewrite and (args.apple_intelligence or args.polish_model):
        parser.error("--rewrite cannot be combined with --apple-intelligence or --polish-model")
    if args.rewrite_directions and not args.rewrite:
        parser.error("--rewrite-directions requires --rewrite")
    if args.expect_apple_unavailable and not args.apple_intelligence:
        parser.error("--expect-apple-unavailable requires --apple-intelligence")
    with (args.app / "Info.plist").open("rb") as file:
        information = plistlib.load(file)
        bundle = information["CFBundleIdentifier"]
        executable = information["CFBundleExecutable"]
    build = root / ".build"
    build.mkdir(exist_ok=True)
    fixture = build / "phone-generated-speech.caf"
    suffix = ("-rewrite-" + args.rewrite_provider) if args.rewrite else "-apple-intelligence" if args.apple_intelligence else "-polished" if args.polish_model else ""
    report = build / ("phone-" + args.model + suffix + ".json")
    report.write_text("{}\n")

    def command(*arguments, check=True, timeout=30):
        result = subprocess.run(list(arguments), capture_output=True, text=True, timeout=timeout + 5)
        if check and result.returncode:
            raise SystemExit((result.stderr or result.stdout).strip() or f"Command failed: {arguments[0]}")
        return result

    def device(*arguments, check=True, timeout=30):
        return command("xcrun", "devicectl", "device", *arguments,
                       "--device", args.device, "--timeout", str(timeout), check=check, timeout=timeout)

    def copy(direction, source, destination, check=True):
        return device("copy", direction, "--domain-type", "appDataContainer",
                      "--domain-identifier", bundle, "--source", str(source),
                      "--destination", str(destination), check=check)

    command("/usr/bin/say", "-o", str(fixture), args.phrase)
    copy("to", fixture, "Documents/integration-fixture.caf")
    # Clear the old report so a previous test cannot count as this test's result.
    copy("to", report, "Documents/integration-result.json")
    with tempfile.TemporaryDirectory(prefix="phone-fixture-", dir=build) as temporary:
        run_directory = Path(temporary)
        launch_record = run_directory / "launch.json"
        process = None
        completed = False
        try:
            arguments = ["xcrun", "devicectl", "device", "process", "launch", "--device", args.device,
                         "--timeout", "30", "--terminate-existing", "--json-output", str(launch_record), bundle,
                         "--integration-audio", "integration-fixture.caf", "--integration-model", args.model]
            if args.polish_model:
                arguments += ["--integration-polish-model", args.polish_model]
            if args.apple_intelligence:
                arguments += ["--integration-apple-intelligence"]
            arguments += ["--integration-language", args.language]
            if args.cache_text_model:
                arguments += ["--integration-cache-text-model", args.cache_text_model]
            if args.rewrite:
                arguments += ["--integration-rewrite-check", "--integration-rewrite-directions", args.rewrite_directions,
                              "--integration-rewrite-provider", args.rewrite_provider,
                      "--integration-rewrite-goal", args.rewrite_goal]
            command(*arguments)
            process = launched_process(launch_record, executable)
            if process is None:
                raise SystemExit("The fixture launched without usable process metadata. Close wisprM manually before normal use.")
            (build / (report.stem + "-launch.json")).write_text(launch_record.read_text())
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
                        validate_transcription(result, model=args.model, apple=args.apple_intelligence,
                            local=bool(args.polish_model), expect_apple_unavailable=args.expect_apple_unavailable,
                            cache_text=bool(args.cache_text_model),
                                               rewrite=args.rewrite, rewrite_provider=args.rewrite_provider)
                        print("Real iPhone transcription passed.", flush=True)
                        completed = True
                        return
                time.sleep(3)
            raise SystemExit("Timed out. Keep the phone unlocked with wisprM in the foreground and inspect the app.")
        finally:
            # A CLI timeout can still leave a successful launch JSON behind.
            process = process or launched_process(launch_record, executable)
            if process is not None:
                cleaned = stop_owned_process(device, process, run_directory)
                if not cleaned:
                    message = ("Could not verify fixture teardown for PID " + str(process["processIdentifier"])
                               + ". Close wisprM from the app switcher before using it normally.")
                    if completed:
                        raise SystemExit(message)
                    print(message, file=sys.stderr)



if __name__ == "__main__":
    main()
