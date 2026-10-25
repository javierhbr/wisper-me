"""Debug fixture report checks and physical-phone process ownership."""
import json
from pathlib import Path
import time
import subprocess


def validate_transcription(result, *, model, apple=False, local=False,
                           expect_apple_unavailable=False, cache_text=False, rewrite=False, rewrite_provider=None):
    """Check real app reports; never manufacture a successful model response."""
    def require(condition, message):
        if not condition:
            raise SystemExit(message)

    if "recordingScreenAwakePolicyVerified" in result:
        require(result["recordingScreenAwakePolicyVerified"] is True,
                "Recording screen-awake override did not restore the previous auto-lock setting.")
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


    if rewrite:
        original, proposal = result.get("rewriteOriginal"), result.get("rewriteProposal")
        if isinstance(original, str) and isinstance(proposal, str):
            require(" ".join(original.split()) != " ".join(proposal.split()),
                    "The model returned unchanged text; no successful rewrite should be claimed.")
        require(result.get("rewriteRequested") is True and result.get("rewriteCompleted") is True,
                "Manual rewrite did not complete; a retained transcript does not establish rewrite success.")
        require(isinstance(original, str) and original.strip()
                and isinstance(proposal, str) and proposal.strip() and result.get("rewriteError") == "",
                "Manual rewrite must return a complete nonempty proposal without a rewrite error.")
        for field in ("rewritePreviewPreservedOriginal", "rewritePreviewPreservedHistory", "rewritePreviewPreservedShared"):
            require(result.get(field) is True, "Rewrite preview changed original text or delivery state: " + field)
        require(result.get("rewriteUnchangedProposalRejected") is True
                and result.get("rewriteRerunFromPreviewVerified") is True,
                "Unchanged proposals must remain unpublished and allow another explicit rewrite.")
        require(result.get("rewriteCancelBeforeStartPreservedOriginal") is True,
                "Cancelling a queued rewrite must preserve the original without starting a provider request.")
        require(result.get("rewriteAccepted") is True and result.get("rewriteUndoRestoredOriginal") is True
                and text == original,
                "Manual rewrite must be accepted explicitly, then Undo must restore the exact original.")
        require(result.get("rewriteAutomaticPolishingMode") == "Local cleanup only"
                and result.get("polishingCompleted") is False,
                "Manual rewriting must not enable or perform automatic polishing.")
        providers = {"apple": "Apple Intelligence", "local": "On-device language model"}
        require(result.get("rewriteProvider") in providers.values(), "Rewrite used an unexpected provider.")
        if rewrite_provider is not None:
            require(rewrite_provider in providers and result.get("rewriteProvider") == providers[rewrite_provider],
                    "Rewrite did not use the requested provider.")

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
