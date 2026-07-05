from pathlib import Path
import sys
import tempfile
import time


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "reporting"))

from build_guanbing_monthly_report import find_latest_image as find_guanbing_image  # noqa: E402
from build_monthly_report import find_latest_image as find_hongtang_image  # noqa: E402
from report_artifact_resolver import find_latest_image as find_report_image  # noqa: E402


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
        emf = folder / "GB-RTS-G05-001-01_20260326_20260426.emf"
        time.sleep(0.02)
        emf.write_bytes(b"vector")

        assert find_report_image(root, "plots", "GB-RTS-G05-001-01").path == stable
        assert find_guanbing_image(root, "plots", "GB-RTS-G05-001-01") == stable

        selected, lookup = find_hongtang_image(root, "plots", "GB-RTS-G05-001-01_")
        assert selected == stable
        assert str(stable) in lookup["matched_files"]


def test_guanbing_deflection_split_dirs_are_looked_up_directly():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        raw_dir = root / "时程曲线_挠度_组图_原始"
        filt_dir = root / "时程曲线_挠度_组图_滤波"
        raw_dir.mkdir()
        filt_dir.mkdir()
        raw = raw_dir / "Defl_G1_Orig_20260401_20260430.jpg"
        filt = filt_dir / "Defl_G1_Filt_20260401_20260430.jpg"
        raw.write_bytes(b"raw")
        filt.write_bytes(b"filt")

        assert find_guanbing_image(root, "时程曲线_挠度_组图_原始", "Defl_G1_Orig") == raw
        assert find_guanbing_image(root, "时程曲线_挠度_组图_滤波", "Defl_G1_Filt") == filt


if __name__ == "__main__":
    test_stable_image_name_is_accepted_by_report_finders()
    test_guanbing_deflection_split_dirs_are_looked_up_directly()
    print("report image lookup smoke ok")
