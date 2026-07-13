from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from workbench.profile_audit import ProfileAuditError, load_installed_profile_matrix


PROFILE_IDS = (
    "guanbing",
    "hongtang",
    "jiulongjiang",
    "shuixianhua",
    "chongyangxi",
    "zhishan",
    "future_bridge",
)


def _catalog_payload(profile_ids: tuple[str, ...] = PROFILE_IDS) -> dict[str, object]:
    profiles = []
    for index, bridge_id in enumerate(profile_ids):
        report_capable = bridge_id != "chongyangxi"
        profiles.append(
            {
                "bridge_id": bridge_id,
                "bridge_name": bridge_id,
                "default_config": f"config/{bridge_id}.json",
                "report_gui_type": f"report_{index}" if report_capable else "",
                "report_template": f"reports/{bridge_id}.docx" if report_capable else "",
            }
        )
    return {"schema_version": 1, "profiles": profiles}


def _matrix_payload(profile_ids: tuple[str, ...] = PROFILE_IDS) -> dict[str, object]:
    profiles = []
    report_capable_count = 0
    for index, bridge_id in enumerate(profile_ids):
        report_capable = bridge_id != "chongyangxi"
        report_capable_count += int(report_capable)
        profiles.append(
            {
                "bridge_id": bridge_id,
                "bridge_name": bridge_id,
                "report_gui_type": f"report_{index}" if report_capable else "",
                "report_capable": report_capable,
                "enabled_module_count": index + 1,
                "config_sha256": str(index) * 64,
                "checks": {"identity": True, "assets": True},
            }
        )
    # Catalog + path groups + four branding assets + one config per bridge +
    # one template per report-capable bridge.
    asset_count = 6 + len(profile_ids) + report_capable_count
    return {
        "schema_version": 1,
        "status": "passed",
        "executable_sha256": "a" * 64,
        "profile_count": len(profile_ids),
        "report_capable_count": report_capable_count,
        "analysis_only_count": len(profile_ids) - report_capable_count,
        "asset_count": asset_count,
        "assets_unchanged": True,
        "elapsed_seconds": 2.5,
        "profiles": profiles,
    }


def _write_catalog(root: Path, profile_ids: tuple[str, ...] = PROFILE_IDS) -> None:
    config = root / "config"
    config.mkdir(parents=True, exist_ok=True)
    (config / "bridge_profiles.json").write_text(
        json.dumps(_catalog_payload(profile_ids)), encoding="utf-8"
    )
    (config / "path_profiles.json").write_text('{"profiles": []}', encoding="utf-8")
    assets = root / "workbench" / "assets"
    assets.mkdir(parents=True)
    for name in ("app_icon.svg", "app_icon.png", "app_icon.ico", "organization_logo.png"):
        (assets / name).write_bytes(name.encode("ascii"))


class WorkbenchProfileAuditTests(unittest.TestCase):
    def test_matrix_is_catalog_driven_and_bound_to_release_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _write_catalog(root)
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
            self.assertEqual(matrix.profile_count, len(PROFILE_IDS))
            self.assertEqual(matrix.report_capable_count, len(PROFILE_IDS) - 1)
            self.assertEqual(matrix.asset_count, 2 * len(PROFILE_IDS) + 5)

            payload = _matrix_payload()
            payload["elapsed_seconds"] = 3.0
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ProfileAuditError, "发布清单不一致"):
                load_installed_profile_matrix(root)

    def test_matrix_rejects_incomplete_profile_checks(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _write_catalog(root)
            payload = _matrix_payload()
            payload["profiles"][2]["checks"]["assets"] = False  # type: ignore[index]
            (root / "workbench_profile_matrix.json").write_text(
                json.dumps(payload), encoding="utf-8"
            )
            with self.assertRaisesRegex(ProfileAuditError, "未完全通过"):
                load_installed_profile_matrix(root)

    def test_matrix_rejects_catalog_addition_until_new_profile_is_checked(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            _write_catalog(root, PROFILE_IDS + ("another_bridge",))
            (root / "workbench_profile_matrix.json").write_text(
                json.dumps(_matrix_payload(PROFILE_IDS)), encoding="utf-8"
            )
            with self.assertRaisesRegex(ProfileAuditError, "项目目录完全一致"):
                load_installed_profile_matrix(root)


if __name__ == "__main__":
    unittest.main()
