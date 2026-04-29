from pathlib import Path
import sys
import tempfile
import time


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "reporting"))

from build_guanbing_monthly_report import find_latest_image as find_guanbing_image  # noqa: E402
from build_monthly_report import find_latest_image as find_hongtang_image  # noqa: E402


def test_stable_image_name_is_accepted_by_report_finders():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        folder = root / "plots"
        folder.mkdir()

        timestamped = folder / "GB-RTS-G05-001-01_20260326_20260426_20260429_153653.jpg"
        stable = folder / "GB-RTS-G05-001-01_20260326_20260426.jpg"
        timestamped.write_bytes(b"old")
        time.sleep(0.02)
        stable.write_bytes(b"new")

        assert find_guanbing_image(root, "plots", "GB-RTS-G05-001-01") == stable

        selected, lookup = find_hongtang_image(root, "plots", "GB-RTS-G05-001-01_")
        assert selected == stable
        assert str(stable) in lookup["matched_files"]


if __name__ == "__main__":
    test_stable_image_name_is_accepted_by_report_finders()
    print("report image lookup smoke ok")
