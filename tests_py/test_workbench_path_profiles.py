from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from workbench.profiles import PathProfileResolver, load_profiles, profile_by_id


ROOT = Path(__file__).resolve().parents[1]


class WorkbenchPathProfileTests(unittest.TestCase):
    def test_shared_catalog_excludes_retired_office_profile(self) -> None:
        resolver = PathProfileResolver(ROOT, {"COMPUTERNAME": "DESKTOP-500FVB6"})
        self.assertIsNone(resolver.by_id("office_pc"))
        self.assertNotIn("办公室电脑", [item.display_name for item in resolver.profiles])
        self.assertEqual(
            {item.profile_id for item in resolver.profiles},
            {"dev_desktop_674s83o", "prod_133", "storage_126"},
        )

    def test_environment_override_precedes_computer_name(self) -> None:
        resolver = PathProfileResolver(
            ROOT,
            {
                "COMPUTERNAME": "DESKTOP-674S83O",
                "GUANBING_PATH_PROFILE": "prod_133",
            },
        )
        profile = resolver.active()
        self.assertIsNotNone(profile)
        assert profile is not None
        self.assertEqual(profile.profile_id, "prod_133")
        self.assertEqual(profile.match_type, "env")

    def test_computer_name_selects_development_paths_and_single_business_config(self) -> None:
        resolver = PathProfileResolver(ROOT, {"COMPUTERNAME": "DESKTOP-674S83O"})
        profile = resolver.active()
        self.assertIsNotNone(profile)
        assert profile is not None
        self.assertEqual(profile.display_name, "开发机")
        guanbing = profile_by_id(load_profiles(ROOT), "guanbing")
        hongtang = profile_by_id(load_profiles(ROOT), "hongtang")
        self.assertEqual(
            resolver.resolve_data_root("guanbing", guanbing.default_data_root, profile),
            str(Path(r"E:\管柄数据\2026年6月")),
        )
        self.assertEqual(
            resolver.resolve_data_root("hongtang", hongtang.default_data_root, profile),
            str(Path(r"E:\洪塘大桥数据\2026年4-6月")),
        )
        self.assertEqual(hongtang.config_path(ROOT), (ROOT / "config" / "hongtang_config.json").resolve())

    def test_local_profile_file_overrides_shared_profile(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config"
            config.mkdir()
            shared = {
                "profiles": [
                    {
                        "profile_id": "future_machine",
                        "display_name": "共享配置",
                        "hostnames": ["FUTURE-PC"],
                        "data_roots": {"guanbing": "E:/shared"},
                    }
                ]
            }
            local = {
                "profiles": [
                    {
                        "profile_id": "future_machine",
                        "display_name": "本机自定义",
                        "hostnames": ["FUTURE-PC"],
                        "data_roots": {"guanbing": "D:/local"},
                    }
                ]
            }
            (config / "path_profiles.json").write_text(json.dumps(shared), encoding="utf-8")
            (config / "path_profiles.local.json").write_text(json.dumps(local), encoding="utf-8")
            resolver = PathProfileResolver(root, {"COMPUTERNAME": "FUTURE-PC"})
            profile = resolver.active()
            self.assertIsNotNone(profile)
            assert profile is not None
            self.assertEqual(profile.display_name, "本机自定义")
            self.assertEqual(
                resolver.resolve_data_root("guanbing", "F:/default", profile),
                str(Path("D:/local")),
            )

    def test_existing_path_tie_prefers_local_override(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config"
            config.mkdir()
            shared_root = root / "shared_data"
            local_root = root / "local_data"
            shared_root.mkdir()
            local_root.mkdir()
            shared = {
                "profiles": [
                    {
                        "profile_id": "same_machine",
                        "display_name": "共享配置",
                        "data_roots": {"guanbing": str(shared_root)},
                    }
                ]
            }
            local = {
                "profiles": [
                    {
                        "profile_id": "same_machine",
                        "display_name": "本机覆盖",
                        "data_roots": {"guanbing": str(local_root)},
                    }
                ]
            }
            (config / "path_profiles.json").write_text(json.dumps(shared), encoding="utf-8")
            (config / "path_profiles.local.json").write_text(json.dumps(local), encoding="utf-8")
            resolver = PathProfileResolver(root, {"COMPUTERNAME": "UNMATCHED-PC"})

            profile = resolver.active()

            self.assertIsNotNone(profile)
            assert profile is not None
            self.assertEqual(profile.display_name, "本机覆盖")
            self.assertEqual(profile.match_type, "path_exists")


if __name__ == "__main__":
    unittest.main()
