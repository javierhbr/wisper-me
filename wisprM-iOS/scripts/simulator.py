#!/usr/bin/env python3
"""Discover and run an installed iPhone simulator by name or explicit UUID."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / ".build/DerivedData/Build/Products/Debug-iphonesimulator/wisprM.app"
def choose(identifier=None, name="iPhone 17 Pro"):
    inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
    devices = [d for values in inventory["devices"].values() for d in values if d.get("isAvailable")]
    candidates = [d for d in devices if d["udid"] == identifier] if identifier else [d for d in devices if d["name"] == name]
    if not candidates: raise SystemExit("No matching simulator. Run xcrun simctl list devices available and pass --simulator UUID.")
    return next((d for d in candidates if d["state"] == "Booted"), candidates[0])
def install(device):
    if not APP.is_dir(): raise SystemExit("Run make build first.")
    identifier = device["udid"]
    if device["state"] != "Booted": subprocess.run(["xcrun", "simctl", "boot", identifier], check=True)
    subprocess.run(["xcrun", "simctl", "bootstatus", identifier, "-b"], check=True)
    subprocess.run(["xcrun", "simctl", "install", identifier, str(APP)], check=True)
    return plistlib.loads((APP/"Info.plist").read_bytes())["CFBundleIdentifier"]
if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("--simulator"); parser.add_argument("--name", default="iPhone 17 Pro")
    args = parser.parse_args(); device = choose(args.simulator or None, args.name); bundle = install(device)
    subprocess.run(["open", "-a", "Simulator"], check=True)
    subprocess.run(["xcrun", "simctl", "launch", device["udid"], bundle], check=True)
