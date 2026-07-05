import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "reporting"))

from reporting_contract import (  # noqa: E402
    contract_precheck_warnings,
    find_latest_reporting_contract,
    output_dirs_by_module,
    reporting_contract_context,
)


class TestReportingContract(unittest.TestCase):
    def test_latest_contract_context_from_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_logs = root / "run_logs"
            run_logs.mkdir()
            contract_path = run_logs / "analysis_reporting_contract_20260523_010101.json"
            contract_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "summary": {"module_count": 1, "point_count": 2, "group_count": 0},
                        "modules": [
                            {
                                "key": "deflection",
                                "output_dir_records": [
                                    {"field": "raw_output_dir", "dir": "deflection_raw", "role": "raw_plot"},
                                    {"field": "filtered_output_dir", "dir": "deflection_filtered", "role": "filtered_plot"},
                                    {"field": "raw_group_output_dir", "dir": "deflection_group_raw", "role": "raw_group_plot"},
                                    {"field": "filtered_group_output_dir", "dir": "deflection_group_filtered", "role": "filtered_group_plot"},
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(find_latest_reporting_contract(root), contract_path)
            context = reporting_contract_context(root)

            self.assertTrue(context["available"])
            self.assertEqual(context["source"], "contract_file")
            self.assertEqual(context["summary"]["module_count"], 1)
            self.assertEqual(
                output_dirs_by_module(context, "deflection"),
                ["deflection_raw", "deflection_filtered", "deflection_group_raw", "deflection_group_filtered"],
            )
            self.assertEqual(output_dirs_by_module(context, "deflection", role="raw_group_plot"), ["deflection_group_raw"])
            self.assertEqual(contract_precheck_warnings(context), [])

    def test_missing_contract_is_nonfatal_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            context = reporting_contract_context(Path(tmp))

            self.assertFalse(context["available"])
            self.assertIn("analysis reporting contract not found", contract_precheck_warnings(context)[0])

    def test_contract_context_from_analysis_manifest(self):
        manifest_context = {
            "manifest": {
                "run_preflight": {
                    "reporting_contract": {
                        "schema_version": 1,
                        "summary": {"module_count": 2},
                        "modules": [{"key": "a"}, {"key": "b"}],
                    }
                }
            }
        }

        context = reporting_contract_context(None, manifest_context)

        self.assertTrue(context["available"])
        self.assertEqual(context["source"], "analysis_manifest")
        self.assertEqual(context["module_count"], 2)


if __name__ == "__main__":
    unittest.main()
