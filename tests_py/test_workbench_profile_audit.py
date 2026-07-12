from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from workbench.profile_audit import ProfileAuditError, load_installed_profile_matrix


def _matrix_payload() -> dict[str, object]:
    profiles = []
    for index, bridge_id in enumerate(
        ("guanbing", "hongtang", "jiulongjiang", "shuixianhua", "chongyangxi", "zhishan")
    ):
        profiles.append(
            {
                "bridge_id": bridge_id,
                "bridge_name": bridge_id,
                "report_gui_type": "" if bridge_id == "chongyangxi" else f"report_{index}",
                "enabled_module_count": index + 1,
                "config_sha256": str(index) * 64,
                "checks": {"identity": True, "assets": True},
            }
        )
    return {
        "schema_version": 1,
        "status": "passed",
        "executable_sha256": "a" * 64,
        "profile_count": 6,
        "report_capable_count": 5,
        "analysis_only_count": 1,
        "asset_count": 12,
        "assets_unchanged": True,
        "elapsed_seconds": 2.5,
        "profiles": profiles,
    }


class WorkbenchProfileAuditTests(unittest.TestCase):
    def test_matrix_is_bound_to_release_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / "workbench_profile_matrix.json"
            path.write_text(json.dumps(_matrix_payload()), encoding="utf-8")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            (root / "release_manifest.json").write_text(
                json.dumps(
                    {
                        "file_inventory": [
                            {"path": path.name, "bytes": path.stat().st_size, "sha256": digest}
                        ]
                    }
                ),
                encoding="utf-8",
            )
            matrix = load_installed_profile_matrix(root)
            self.assertEqual(matrix.profile_count, 6)
            self.assertEqual(matrix.report_capable_count, 5)
            self.assertEqual(matrix.asset_count, 12)

            payload = _matrix_payload()
            payload["elapsed_seconds"] = 3.0
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ProfileAuditError, "发布清单不一致"):
                load_installed_profile_matrix(root)

    def test_matrix_rejects_incomplete_profile_checks(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            payload = _matrix_payload()
            payload["profiles"][2]["checks"]["assets"] = False  # type: ignore[index]
            (root / "workbench_profile_matrix.json").write_text(
                json.dumps(payload), encoding="utf-8"
            )
            with self.assertRaisesRegex(ProfileAuditError, "未完全通过"):
                load_installed_profile_matrix(root)


if __name__ == "__main__":
    unittest.main()
