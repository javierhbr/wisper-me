#!/usr/bin/env python3
"""Install the verified app through a staged copy; never touch user data."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile

APP_NAME = "wisprM.app"
BUNDLE_ID = "com.wisprm.desktop"
PROJECT_ROOT = Path(__file__).resolve().parents[1]


class InstallError(RuntimeError):
    pass


def validate_bundle(app):
    try:
        with (app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise InstallError(f"Not a readable wisprM app bundle: {app}") from error
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "wisprM":
        raise InstallError(f"Refusing to replace an unrelated app: {app}")
    if not (app / "Contents/MacOS/wisprM").is_file():
        raise InstallError(f"The app executable is missing: {app}")


def verify_bundle(app):
    result = subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise InstallError(f"Signature verification failed for {app}. Run make build.")


def is_running(app):
    result = subprocess.run(
        ["/bin/ps", "-axww", "-o", "comm="], capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise InstallError("Could not check running apps. Run installation from a normal Terminal session.")
    executable = str(app / "Contents/MacOS/wisprM")
    return any(line.strip() == executable for line in result.stdout.splitlines())


def install(source, destination):
    source = Path(source).expanduser().resolve()
    destination = Path(destination).expanduser().resolve()
    target = destination / APP_NAME
    if destination.suffix == ".app" or source == target or source in destination.parents:
        raise InstallError("INSTALL_DIR must be a separate Applications directory, not the build app.")
    validate_bundle(source)
    verify_bundle(source)
    destination.mkdir(parents=True, exist_ok=True)
    lock = destination / ".wisprM.install.lock"
    try:
        descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError as error:
        raise InstallError(f"Another installation may be active. Lock file: {lock}") from error
    os.close(descriptor)
    stage = None
    preserve_stage = False
    try:
        if target.is_symlink():
            raise InstallError(f"Refusing to replace an app symlink: {target}")
        if target.exists():
            validate_bundle(target)
            if is_running(target):
                raise InstallError("Quit the installed wisprM app, then run make install again.")
        stage = Path(tempfile.mkdtemp(prefix=".wisprM-stage-", dir=destination))
        staged_app = stage / APP_NAME
        backup = stage / "previous.app"
        shutil.copytree(source, staged_app, symlinks=True, copy_function=shutil.copy2)
        validate_bundle(staged_app)
        verify_bundle(staged_app)
        try:
            if target.exists():
                if is_running(target):
                    raise InstallError("Quit the installed wisprM app, then run make install again.")
                os.replace(target, backup)
            os.replace(staged_app, target)
        except BaseException:
            if backup.exists():
                try:
                    os.replace(backup, target)
                except OSError as rollback_error:
                    preserve_stage = True
                    raise InstallError(f"Installation failed; the previous app is retained at {backup}") from rollback_error
            raise
    finally:
        try:
            if stage is not None and not preserve_stage:
                shutil.rmtree(stage)
        finally:
            lock.unlink(missing_ok=True)
    return target


def clean_build_outputs(root):
    development_app = Path(root) / "dist" / APP_NAME
    if not (Path(root) / "dist").is_symlink() and development_app.is_dir() and is_running(development_app):
        raise InstallError("Quit the development wisprM app before running make clean.")
    for name in (".build", "dist"):
        path = Path(root) / name
        if path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            raise InstallError(f"Refusing to remove unexpected non-directory build output: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    installer = commands.add_parser("install")
    installer.add_argument("--source", required=True)
    installer.add_argument("--destination", required=True)
    commands.add_parser("clean")
    args = parser.parse_args()
    try:
        if args.action == "install":
            print("Installed", install(args.source, args.destination))
        else:
            clean_build_outputs(PROJECT_ROOT)
            print("Removed generated .build/ and dist/ outputs.")
    except (InstallError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit("Installation interrupted."))
    raise SystemExit(main())
