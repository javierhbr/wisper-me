#!/usr/bin/env python3
"""Keep complete Xcode diagnostics on disk and show concise results in the terminal."""
from pathlib import Path
import os
import platform
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
device = len(sys.argv) > 1 and sys.argv[1] == "device"
kind = "device" if device else "simulator"
build = root / ".build"
build.mkdir(exist_ok=True)
log = build / (kind + "-build.log")
arguments = ["xcodebuild", "-quiet", "-skipPackagePluginValidation", "-project", "wisprM.xcodeproj",
    "-scheme", "wisprM", "-configuration", "Release" if device else "Debug", "-destination",
    "generic/platform=iOS" if device else "generic/platform=iOS Simulator", "-derivedDataPath",
    ".build/Device" if device else ".build/DerivedData", "-clonedSourcePackagesDirPath", ".build/Packages",
    "CODE_SIGNING_ALLOWED=NO"]
if not device:
    arguments += ["ARCHS=" + platform.machine(), "ONLY_ACTIVE_ARCH=YES"]
environment = dict(os.environ, SPM_CUDA="0")
print(f"Building {kind}; full log: {log}", flush=True)
with log.open("w") as output:
    result = subprocess.run(arguments + ["build"], cwd=root, env=environment, stdout=output, stderr=subprocess.STDOUT)
lines = log.read_text(errors="replace").splitlines()
if result.returncode:
    errors = [line for line in lines if "error:" in line or "BUILD FAILED" in line]
    print("\n".join(errors[-25:] if errors else lines[-25:]))
    raise SystemExit(result.returncode)
if not device:
    app = build / "DerivedData/Build/Products/Debug-iphonesimulator/wisprM.app"
    for binary, entitlements in [(app/"PlugIns/WisprKeyboard.appex", "WisprKeyboard"), (app, "wisprM")]:
        info = plistlib.loads((binary/"Info.plist").read_bytes())
        values = {"com.apple.security.application-groups": [info["WisprAppGroup"]]}
        expanded = build/(entitlements+"-simulator.xcent")
        expanded.write_bytes(plistlib.dumps(values))
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements", str(expanded), str(binary)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(f"{kind.capitalize()} build passed.")
