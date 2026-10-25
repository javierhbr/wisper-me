import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "local_app", Path(__file__).resolve().parents[1] / "scripts/local-app.py")
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class LocalInstallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="wisprm-install-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "build" / "wisprM.app"
        self.destination = self.root / "Applications with spaces"
        self.app(self.source, "new")
        self.verify = patch.object(installer, "verify_bundle")
        self.verify.start()
        self.addCleanup(self.verify.stop)
        self.running = patch.object(installer, "is_running", return_value=False)
        self.running.start()
        self.addCleanup(self.running.stop)

    def app(self, path, contents, identifier=installer.BUNDLE_ID):
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "wisprM"}))
        (path / "Contents/MacOS/wisprM").write_text(contents)

    def assert_no_install_artifacts(self):
        self.assertFalse((self.destination / ".wisprM.install.lock").exists())
        self.assertEqual(list(self.destination.glob(".wisprM-stage-*")), [])

    def test_install_and_update_preserve_only_the_verified_app(self):
        target = installer.install(self.source, self.destination)
        self.assertEqual((target / "Contents/MacOS/wisprM").read_text(), "new")
        (self.source / "Contents/MacOS/wisprM").write_text("updated")
        installer.install(self.source, self.destination)
        self.assertEqual((target / "Contents/MacOS/wisprM").read_text(), "updated")
        self.assert_no_install_artifacts()

    def test_unrelated_existing_app_is_not_replaced(self):
        target = self.destination / installer.APP_NAME
        self.app(target, "unrelated", identifier="org.example.other")
        with self.assertRaises(installer.InstallError):
            installer.install(self.source, self.destination)
        self.assertEqual((target / "Contents/MacOS/wisprM").read_text(), "unrelated")
        self.assert_no_install_artifacts()

    def test_running_installation_is_not_replaced(self):
        target = self.destination / installer.APP_NAME
        self.app(target, "running")
        with patch.object(installer, "is_running", return_value=True):
            with self.assertRaises(installer.InstallError):
                installer.install(self.source, self.destination)
        self.assertEqual((target / "Contents/MacOS/wisprM").read_text(), "running")
        self.assert_no_install_artifacts()

    def test_failed_replacement_restores_previous_app(self):
        target = self.destination / installer.APP_NAME
        self.app(target, "previous")
        replace = installer.os.replace

        def fail_new_copy(source, destination):
            if Path(source).name == installer.APP_NAME and ".wisprM-stage-" in str(source):
                raise OSError("Simulated replacement failure")
            return replace(source, destination)

        with patch.object(installer.os, "replace", side_effect=fail_new_copy):
            with self.assertRaises(OSError):
                installer.install(self.source, self.destination)
        self.assertEqual((target / "Contents/MacOS/wisprM").read_text(), "previous")
        self.assert_no_install_artifacts()

    def test_invalid_staged_signature_keeps_previous_app(self):
        target = self.destination / installer.APP_NAME
        self.app(target, "previous")
        with patch.object(installer, "verify_bundle", side_effect=[None, installer.InstallError("Invalid copy")]):
            with self.assertRaises(installer.InstallError):
                installer.install(self.source, self.destination)
        self.assertEqual((target / "Contents/MacOS/wisprM").read_text(), "previous")
        self.assert_no_install_artifacts()

    def test_failed_rollback_retains_the_previous_copy(self):
        target = self.destination / installer.APP_NAME
        self.app(target, "previous")
        replace = installer.os.replace

        def fail_after_backup(source, destination):
            if Path(source).resolve() == target.resolve():
                return replace(source, destination)
            raise OSError("Simulated replacement and rollback failure")

        with patch.object(installer.os, "replace", side_effect=fail_after_backup):
            with self.assertRaisesRegex(installer.InstallError, "retained"):
                installer.install(self.source, self.destination)
        backups = list(self.destination.glob(".wisprM-stage-*/previous.app"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "Contents/MacOS/wisprM").read_text(), "previous")
        self.assertFalse((self.destination / ".wisprM.install.lock").exists())

    def test_source_and_symlink_destinations_are_rejected(self):
        with self.assertRaises(installer.InstallError):
            installer.install(self.source, self.source.parent)
        self.destination.mkdir()
        (self.destination / installer.APP_NAME).symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(installer.InstallError):
            installer.install(self.source, self.destination)
        self.assertTrue(self.source.exists())
        self.assert_no_install_artifacts()

    def test_clean_does_not_follow_build_output_symlinks(self):
        project = self.root / "project"
        (project / ".build").mkdir(parents=True)
        outside = self.root / "untouched"
        outside.mkdir()
        (outside / "keep.txt").write_text("keep")
        (project / "dist").symlink_to(outside, target_is_directory=True)
        installer.clean_build_outputs(project)
        self.assertFalse((project / ".build").exists())
        self.assertFalse((project / "dist").is_symlink())
        self.assertEqual((outside / "keep.txt").read_text(), "keep")


    def test_clean_refuses_to_remove_a_running_development_app(self):
        project = self.root / "project"
        self.app(project / "dist" / installer.APP_NAME, "running")
        with patch.object(installer, "is_running", return_value=True):
            with self.assertRaises(installer.InstallError):
                installer.clean_build_outputs(project)
        self.assertTrue((project / "dist" / installer.APP_NAME).is_dir())


if __name__ == "__main__":
    unittest.main()
