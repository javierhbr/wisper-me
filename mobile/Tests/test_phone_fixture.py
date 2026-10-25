import json
from pathlib import Path
import tempfile
import types
import unittest
import sys
import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from phone_fixture import launched_process, stop_owned_process, validate_transcription


class FakeDevice:
    def __init__(self, executable, *, ignore_term=False, query_fails=False):
        self.executable = executable
        self.alive = True
        self.ignore_term = ignore_term
        self.query_fails = query_fails
        self.forced = False

    def __call__(self, *arguments, **options):
        if arguments[:2] == ("info", "processes"):
            if self.query_fails:
                return types.SimpleNamespace(returncode=1)
            destination = Path(arguments[arguments.index("--json-output") + 1])
            rows = [{"processIdentifier": 41, "executable": self.executable}] if self.alive else []
            destination.write_text(json.dumps({"result": {"runningProcesses": rows}}))
        elif arguments[:2] == ("process", "terminate"):
            if "--kill" in arguments:
                self.forced = True
                self.alive = False
            elif not self.ignore_term:
                self.alive = False
        else:
            raise AssertionError("Unexpected fake command")
        return types.SimpleNamespace(returncode=0)


class PhoneFixtureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.executable = "file:///private/app/wisprM.app/wisprM"
        self.process = {"processIdentifier": 41, "executable": self.executable}

    def test_launch_ownership_uses_success_json_and_rejects_invalid_pid(self):
        record = self.path / "launch.json"
        value = {"info": {"outcome": "success"}, "result": {"process": self.process}}
        record.write_text(json.dumps(value))
        self.assertEqual(launched_process(record, "wisprM"), self.process)
        value["result"]["process"] = dict(self.process, processIdentifier=True)
        record.write_text(json.dumps(value))
        self.assertIsNone(launched_process(record, "wisprM"))

    def test_owned_process_is_stopped_and_exit_verified(self):
        device = FakeDevice(self.executable)
        self.assertTrue(stop_owned_process(device, self.process, self.path))
        self.assertFalse(device.alive)
        self.assertFalse(device.forced)

    def test_reused_pid_never_terminates_another_executable(self):
        device = FakeDevice("file:///private/other.app/other")
        self.assertTrue(stop_owned_process(device, self.process, self.path))
        self.assertTrue(device.alive)

    def test_missing_metadata_fails_closed_without_terminating(self):
        device = FakeDevice(self.executable, query_fails=True)
        self.assertFalse(stop_owned_process(device, self.process, self.path))
        self.assertTrue(device.alive)

    def test_unresponsive_owned_fixture_has_bounded_forced_cleanup(self):
        device = FakeDevice(self.executable, ignore_term=True)
        self.assertTrue(stop_owned_process(device, self.process, self.path))
        self.assertTrue(device.forced)
        self.assertFalse(device.alive)

    def test_successful_apple_polishing_keeps_asr_without_pressure(self):
        result = self.result()
        validate_transcription(result, model="whisper-tiny", apple=True)
        result["loadedModel"] = ""
        with self.assertRaises(SystemExit):
            validate_transcription(result, model="whisper-tiny", apple=True)
        result["resourcePressureDuringRun"] = True
        validate_transcription(result, model="whisper-tiny", apple=True)

    def test_unavailable_apple_preserves_text_and_engine(self):
        result = dict(self.result(), appleIntelligenceAvailable=False, polishingCompleted=False,
                      error="Apple Intelligence is unavailable", text="Original cleanup.",
                      unpolishedText="Original cleanup.")
        validate_transcription(result, model="whisper-tiny", apple=True, expect_apple_unavailable=True)
        result["text"] = "Different provider output."
        with self.assertRaises(SystemExit):
            validate_transcription(result, model="whisper-tiny", apple=True, expect_apple_unavailable=True)

    def test_text_cache_download_never_warms_the_model(self):
        result = dict(self.result(), textCacheDownloadCompleted=True, textModelLoaded=False,
                      textCacheDownloadRetainedSpeech=True)
        validate_transcription(result, model="whisper-tiny", cache_text=True)
        result["textModelLoaded"] = True
        with self.assertRaises(SystemExit):
            validate_transcription(result, model="whisper-tiny", cache_text=True)

    @staticmethod
    def rewrite_result():
        return dict(PhoneFixtureTests.result(), text="Original cleanup.", polishingCompleted=False,
                    rewriteRequested=True, rewriteProvider="Apple Intelligence",
                    rewriteOriginal="Original cleanup.", rewriteProposal="A clearly organized idea.",
                    rewriteError="", rewriteCompleted=True, rewritePreviewPreservedOriginal=True,
                    rewritePreviewPreservedHistory=True, rewritePreviewPreservedShared=True,
                    rewriteCancelBeforeStartPreservedOriginal=True,
                    rewriteAccepted=True, rewriteUndoRestoredOriginal=True,
                    rewriteUnchangedProposalRejected=True, rewriteRerunFromPreviewVerified=True,
                    rewriteAutomaticPolishingMode="Local cleanup only")

    def test_recording_screen_awake_policy_must_restore_previous_value(self):
        validate_transcription(dict(self.result(), recordingScreenAwakePolicyVerified=True), model="whisper-tiny")
        with self.assertRaises(SystemExit):
            validate_transcription(dict(self.result(), recordingScreenAwakePolicyVerified=False), model="whisper-tiny")

    def test_rewrite_requires_a_real_successful_proposal_and_undo(self):
        validate_transcription(self.rewrite_result(), model="whisper-tiny", rewrite=True)
        for key, value in [("rewriteRequested", False), ("rewriteCompleted", False),
                           ("rewriteProposal", ""), ("rewriteProposal", "Original cleanup."), ("rewriteOriginal", ""),
                           ("rewriteError", "Model unavailable"), ("rewriteAccepted", False), ("rewriteUnchangedProposalRejected", False), ("rewriteRerunFromPreviewVerified", False),
                           ("rewriteCancelBeforeStartPreservedOriginal", False),
                           ("rewriteUndoRestoredOriginal", False), ("text", "Accepted rewrite")]:
            with self.subTest(field=key), self.assertRaises(SystemExit):
                validate_transcription(dict(self.rewrite_result(), **{key: value}),
                                       model="whisper-tiny", rewrite=True)

    def test_rewrite_preview_preserves_every_delivery_boundary(self):
        for key in ["rewritePreviewPreservedOriginal", "rewritePreviewPreservedHistory", "rewritePreviewPreservedShared"]:
            with self.subTest(field=key), self.assertRaises(SystemExit):
                validate_transcription(dict(self.rewrite_result(), **{key: False}),
                                       model="whisper-tiny", rewrite=True)

    def test_rewrite_never_enables_automatic_polishing_or_switches_provider(self):
        with self.assertRaises(SystemExit):
            validate_transcription(dict(self.rewrite_result(), rewriteAutomaticPolishingMode="Apple Intelligence"),
                                   model="whisper-tiny", rewrite=True)
        with self.assertRaises(SystemExit):
            validate_transcription(dict(self.rewrite_result(), polishingCompleted=True),
                                   model="whisper-tiny", rewrite=True)
        local = dict(self.rewrite_result(), rewriteProvider="On-device language model")
        validate_transcription(local, model="whisper-tiny", rewrite=True, rewrite_provider="local")
        with self.assertRaises(SystemExit):
            validate_transcription(local, model="whisper-tiny", rewrite=True, rewrite_provider="apple")
        with self.assertRaises(SystemExit):
            validate_transcription(self.result(), model="whisper-tiny", rewrite=True)

    def test_rewrite_driver_rejects_combined_automatic_polishing_flags(self):
        scripts = Path(__file__).resolve().parents[1] / "scripts"
        for name in ["integration-transcription.py", "integration-phone.py"]:
            extra = ["--device", "unused-fixture-device"] if name == "integration-phone.py" else []
            for flags in [["--apple-intelligence"], ["--polish-model", "test/model"]]:
                with self.subTest(script=name, flags=flags):
                    result = subprocess.run([sys.executable, str(scripts / name), *extra, "--rewrite", *flags],
                                            capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("--rewrite cannot be combined", result.stderr)

    @staticmethod
    def result():
        # Report-contract tests only; actual fixture scripts always read real app output.
        return {"model": "whisper-tiny", "loadedModel": "whisper-tiny", "canDictate": True,
                "text": "Corrected transcript.", "unpolishedText": "Original cleanup.",
                "error": "", "polishingCompleted": True, "polishingProvider": "Apple Intelligence",
                "resourcePressureDuringRun": False}


if __name__ == "__main__":
    unittest.main()
