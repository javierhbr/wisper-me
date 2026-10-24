import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ProjectGenerationTests(unittest.TestCase):
    def test_signing_survives_repeated_generation(self):
        source = Path(__file__).resolve().parents[1] / "scripts/generate-project.py"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "scripts").mkdir()
            shutil.copyfile(source, root / "scripts/generate-project.py")
            settings = {"bundleIdentifier": "com.example.wisprtest", "appGroup": "group.com.example.wisprtest", "developmentTeam": "TESTTEAM12"}
            (root / "signing.local.json").write_text(json.dumps(settings))
            environment = dict(os.environ, WISPRM_DEVELOPMENT_TEAM="")
            for _ in range(2):
                subprocess.run(["python3", str(root / "scripts/generate-project.py")], check=True, env=environment, stdout=subprocess.DEVNULL)
                data = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(root / "wisprM.xcodeproj/project.pbxproj")])
                objects = json.loads(data)["objects"]
                for name, identifier in [("wisprM", settings["bundleIdentifier"]), ("WisprKeyboard", settings["bundleIdentifier"] + ".keyboard")]:
                    target = next(value for value in objects.values() if value.get("isa") == "PBXNativeTarget" and value["name"] == name)
                    configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
                    for key in configurations:
                        values = objects[key]["buildSettings"]
                        self.assertEqual(values["PRODUCT_BUNDLE_IDENTIFIER"], identifier)
                        self.assertEqual(values["DEVELOPMENT_TEAM"], settings["developmentTeam"])
                        self.assertEqual(values["WISPRM_APP_GROUP"], settings["appGroup"])
            self.assertEqual(json.loads((root / "signing.local.json").read_text()), settings)

    def test_project_generation_is_deterministic(self):
        source = Path(__file__).resolve().parents[1] / "scripts/generate-project.py"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); (root / "scripts").mkdir()
            shutil.copyfile(source, root / "scripts/generate-project.py")
            subprocess.run(["python3", str(root / "scripts/generate-project.py")], check=True, stdout=subprocess.DEVNULL)
            original = (root / "wisprM.xcodeproj/project.pbxproj").read_bytes()
            subprocess.run(["python3", str(root / "scripts/generate-project.py")], check=True, stdout=subprocess.DEVNULL)
            self.assertEqual(original, (root / "wisprM.xcodeproj/project.pbxproj").read_bytes())


if __name__ == "__main__":
    unittest.main()
