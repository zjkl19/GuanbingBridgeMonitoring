from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from prepare_hongtang_typhoon_data_root import prepare_data_root, sha256_file  # noqa: E402


START = datetime(2026, 7, 10, 23, 20, 1)
END = datetime(2026, 7, 10, 23, 20, 2, 500000)


def sample_text() -> str:
    return "\r\n".join(
        [
            "导出元数据",
            "绝对时间,值",
            "2026-07-10 23:20:00.999,0",
            "2026-07-10 23:20:01.000,1",
            "2026-07-10 23:20:02.000,2",
            "2026-07-10 23:20:02.500,3",
            "2026-07-10 23:20:02.501,4",
            "2026-13-01 00:00:00.000,5",
        ]
    ) + "\r\n"


def create_source(root: Path) -> dict[Path, str]:
    day_root = root / "2026-07-11"
    wave = day_root / "波形"
    feature = day_root / "特征值"
    wave.mkdir(parents=True)
    feature.mkdir(parents=True)
    wave_zip = wave / "wave.zip"
    feature_zip = feature / "feature.zip"
    with ZipFile(wave_zip, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("nested/风速_162.csv", sample_text().encode("utf-16"))
        archive.writestr("readme.txt", "not a CSV")
    with ZipFile(feature_zip, "w", compression=ZIP_DEFLATED) as archive:
        archive.writestr("索力_1.csv", sample_text().encode("utf-8-sig"))
        archive.writestr("索力_2.csv", sample_text().encode("gb18030"))
    (wave / "condition.param").write_bytes(b"wave-condition\x00")
    (feature / "condition.param").write_bytes(b"feature-condition\x00")
    return {wave_zip: sha256_file(wave_zip), feature_zip: sha256_file(feature_zip)}


class PrepareHongtangTyphoonDataRootTests(unittest.TestCase):
    def test_stream_filter_manifest_condition_and_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            source = temp / "source"
            output = temp / "prepared"
            source_hashes = create_source(source)

            manifest = prepare_data_root(
                source,
                output,
                ["2026-07-11"],
                START,
                END,
                copy_condition_param=True,
            )

            self.assertEqual(manifest["status"], "ok")
            self.assertEqual(
                manifest["totals"],
                {
                    "zip_count": 2,
                    "zip_entry_count": 4,
                    "csv_entry_count": 3,
                    "source_rows": 15,
                    "kept_rows": 9,
                    "rejected_rows": 6,
                    "non_data_rows": 6,
                    "invalid_timestamp_rows": 3,
                },
            )
            entries = [
                entry
                for zip_record in manifest["zips"]
                for entry in zip_record["entries"]
                if entry["status"] == "prepared"
            ]
            self.assertEqual(len(entries), 3)
            for entry in entries:
                self.assertEqual(entry["source_rows"], 5)
                self.assertEqual(entry["kept_rows"], 3)
                self.assertEqual(entry["rejected_rows"], 2)
                self.assertEqual(entry["source_first_time"], "2026-07-10 23:20:00.999000")
                self.assertEqual(entry["source_last_time"], "2026-07-10 23:20:02.501000")
                self.assertEqual(entry["kept_first_time"], "2026-07-10 23:20:01")
                self.assertEqual(entry["kept_last_time"], "2026-07-10 23:20:02.500000")

            expected_lines = [
                "2026-07-10 23:20:01.000,1",
                "2026-07-10 23:20:02.000,2",
                "2026-07-10 23:20:02.500,3",
            ]
            outputs = {
                output / "2026-07-11" / "波形" / "风速_162.csv": "utf-16",
                output / "2026-07-11" / "特征值" / "索力_1.csv": "utf-8-sig",
                output / "2026-07-11" / "特征值" / "索力_2.csv": "gb18030",
            }
            for path, encoding in outputs.items():
                self.assertEqual(path.read_text(encoding=encoding).splitlines(), expected_lines)
            self.assertEqual(
                (output / "2026-07-11" / "波形" / "condition.param").read_bytes(),
                b"wave-condition\x00",
            )
            self.assertTrue((output / "prepare_hongtang_typhoon_data_manifest.json").is_file())
            for source_zip, before_hash in source_hashes.items():
                self.assertEqual(sha256_file(source_zip), before_hash)

            with self.assertRaises(FileExistsError):
                prepare_data_root(source, output, ["2026-07-11"], START, END)
            overwritten = prepare_data_root(
                source,
                output,
                ["2026-07-11"],
                START,
                END,
                copy_condition_param=True,
                overwrite=True,
            )
            self.assertEqual(overwritten["status"], "ok")

    def test_dry_run_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            source = temp / "source"
            output = temp / "does-not-exist"
            create_source(source)

            manifest = prepare_data_root(
                source,
                output,
                ["2026-07-11"],
                START,
                END,
                copy_condition_param=True,
                dry_run=True,
            )

            self.assertEqual(manifest["status"], "dry-run")
            self.assertIsNone(manifest["manifest_path"])
            self.assertEqual(manifest["totals"]["kept_rows"], 9)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
