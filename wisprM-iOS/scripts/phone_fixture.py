"""Debug fixture report checks and physical-phone process ownership."""
import json
from pathlib import Path
import time
import subprocess


def validate_transcription(result, *, model, apple=False, local=False,
                           expect_apple_unavailable=False, cache_text=False):
    """Check real app reports; never manufacture a successful model response."""
    def require(condition, message):
        if not condition:
            raise SystemExit(message)

    text = result.get("text")
    require(result.get("model") == model and isinstance(text, str) and text.strip(),
            "The requested speech model did not produce a transcript.")
    if expect_apple_unavailable:
        require(apple and result.get("appleIntelligenceAvailable") is False
                and result.get("polishingCompleted") is False and result.get("error")
                and result.get("text") == result.get("unpolishedText")
                and result.get("polishingProvider") == "Apple Intelligence",
                "Unavailable Apple Intelligence must preserve cleanup without switching provider.")
    else:
        require(not result.get("error"), "Inference reported an error; see the report above.")
        if apple or local:
            require(result.get("polishingCompleted") is True,
                    "The transcript was preserved, but requested polishing did not complete.")
    require(result.get("canDictate") is True, "The next recording cannot restore the cached model.")
    if apple:
        require("resourcePressureDuringRun" in result, "Rebuild the app with resource-pressure reporting.")
        if not result["resourcePressureDuringRun"]:
            require(result.get("loadedModel") == model,
                    "Apple polishing unnecessarily discarded the ready speech engine.")
    if cache_text:
        require(result.get("textCacheDownloadCompleted") is True and result.get("textModelLoaded") is False,
                "Text-model download must cache files without warming the inference model.")
        if not result.get("resourcePressureDuringRun", False):
            require(result.get("textCacheDownloadRetainedSpeech") is True and result.get("loadedModel") == model,
                    "Caching a text model must retain the ready speech engine.")


def launched_process(path: Path, executable_name: str):
    """Read only Apple's versioned JSON interface, never terminal output."""
    try:
        value = json.loads(path.read_text())
        process = value["result"]["process"]
        pid, executable = process["processIdentifier"], process["executable"]
        if (value["info"]["outcome"] == "success" and type(pid) is int and pid > 0
                and isinstance(executable, str) and executable.startswith("file://")
                and ".app/" in executable and executable.endswith("/" + executable_name)):
            return process
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def stop_owned_process(device, process, directory: Path) -> bool:
    """Terminate only the exact process launched for this fixture, with bounded waits.

    Recheck its executable to protect against PID reuse. Failure is surfaced to the
    caller instead of pretending a clipboard-suppressed fixture session is normal.
    """
    pid, executable = process["processIdentifier"], process["executable"]
    snapshot = directory / "owned-process.json"

    def current():
        snapshot.unlink(missing_ok=True)
        result = device("info", "processes", "--filter", f"processIdentifier == {pid}",
                        "--json-output", str(snapshot), check=False, timeout=8)
        if result.returncode:
            return None
        try:
            rows = json.loads(snapshot.read_text())["result"]["runningProcesses"]
            if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
                return None
            return any(row.get("processIdentifier") == pid and row.get("executable") == executable
                       for row in rows)
        except (OSError, ValueError, KeyError, TypeError):
            return None

    try:
        alive = current()
        if alive is not True:
            return alive is False
        result = device("process", "terminate", "--pid", str(pid), check=False, timeout=8)
        if result.returncode:
            return current() is False
        for _ in range(3):
            time.sleep(0.2)
            alive = current()
            if alive is not True:
                return alive is False
        # Only this still-matching, explicitly launched fixture process is killed.
        device("process", "terminate", "--pid", str(pid), "--kill", check=False, timeout=8)
        time.sleep(0.2)
        return current() is False
    except (OSError, TimeoutError, subprocess.TimeoutExpired):
        return False
