#!/usr/bin/env python3
"""Reproducible lock generation from the verified venv and official package metadata."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import quote
from urllib.request import urlopen

def read_json(url):
    with urlopen(url, timeout=30) as response:
        return json.load(response)

def package_lock(package):
    name, version = package
    data = read_json("https://pypi.org/pypi/" + quote(name, safe="") + "/" + quote(version, safe="") + "/json")
    hashes = sorted({item["digests"]["sha256"] for item in data["urls"] if item["packagetype"] == "bdist_wheel"})
    if not hashes or any(not re.fullmatch("[0-9a-f]{64}", value) for value in hashes):
        raise RuntimeError("No verified wheel hashes for " + name)
    return name + "==" + version + " \\\n" + " \\\n".join("    --hash=sha256:" + value for value in hashes)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", required=True)
    parser.add_argument("--models-only", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    packages = []
    if not args.models_only:
        raw = subprocess.check_output([args.python, "-c",
            "import importlib.metadata,json; print(json.dumps(sorted({d.metadata['Name']:d.version for d in importlib.metadata.distributions()}.items())))"], text=True)
        packages = json.loads(raw)
        with ThreadPoolExecutor(max_workers=6) as pool:
            entries = list(pool.map(package_lock, packages))
        lock = "# macOS arm64; Python 3.12 or 3.13. Generated from the verified runtime.\n" + "\n\n".join(entries) + "\n"
        (root / "runtime/requirements.lock.txt").write_text(lock)
    models = {
        "mlx-community/whisper-tiny": {"revision": "78c52ab98ca87f570bc57ad852e15ef7060f9f76"},
        "mlx-community/parakeet-tdt-0.6b-v3": {"revision": "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15"},
    }
    for model in ["mlx-community/whisper-base-mlx", "mlx-community/whisper-small-mlx"]:
        revision = read_json("https://huggingface.co/api/models/" + model)["sha"]
        if not re.fullmatch("[0-9a-f]{40}", revision):
            raise RuntimeError("Invalid model revision")
        models[model] = {"revision": revision}
    (root / "runtime/models.lock.json").write_text(json.dumps({"models": models}, indent=2) + "\n")
    print("Locked", len(packages), "packages with wheel hashes and", len(models), "default model revisions.")

if __name__ == "__main__":
    main()
