import json
import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_jlj_monthly_report import load_json as load_jlj_json  # noqa: E402
from build_monthly_report import load_json as load_hongtang_json  # noqa: E402
from build_shuixianhua_monthly_report import load_json as load_shuixianhua_json  # noqa: E402


class ReportJsonEncodingTest(unittest.TestCase):
    def test_report_config_loaders_accept_utf8_bom(self):
        payload = {"bridge": "洪塘大桥", "enabled": True}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8-sig")

            for loader in (load_hongtang_json, load_jlj_json, load_shuixianhua_json):
                with self.subTest(loader=loader.__module__):
                    self.assertEqual(loader(path), payload)


if __name__ == "__main__":
    unittest.main()
