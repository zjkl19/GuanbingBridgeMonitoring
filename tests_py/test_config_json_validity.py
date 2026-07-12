from __future__ import annotations

import json
import unittest
from pathlib import Path


class ConfigJsonValidityTests(unittest.TestCase):
    def test_runtime_config_json_files_are_valid_objects(self) -> None:
        root = Path(__file__).resolve().parents[1] / "config"
        paths = sorted(root.glob("*_config.json"))
        paths.extend([root / "bridge_profiles.json", root / "path_profiles.json"])
        self.assertGreaterEqual(len(paths), 8)
        for path in paths:
            with self.subTest(path=path.name):
                payload = json.loads(path.read_text(encoding="utf-8-sig"))
                self.assertIsInstance(payload, dict)


if __name__ == "__main__":
    unittest.main()
