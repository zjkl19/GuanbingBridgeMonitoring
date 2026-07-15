from __future__ import annotations

import argparse
import unittest
from pathlib import Path


DEFAULT_TEST_DIRS = ("tests_py", "tests")


def build_suite(
    repo_root: Path,
    *,
    test_dirs: tuple[str, ...] = DEFAULT_TEST_DIRS,
    pattern: str = "test_*.py",
    loader: unittest.TestLoader | None = None,
) -> unittest.TestSuite:
    """Discover every maintained Python test location."""

    root = repo_root.resolve()
    selected_loader = loader or unittest.defaultTestLoader
    suite = unittest.TestSuite()
    for relative in test_dirs:
        start_dir = root / relative
        if not start_dir.is_dir():
            raise FileNotFoundError(f"Python test directory does not exist: {start_dir}")
        suite.addTests(
            selected_loader.discover(
                start_dir=str(start_dir),
                pattern=pattern,
                top_level_dir=str(root),
            )
        )
    return suite


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run all maintained Guanbing Python tests.")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--verbosity", type=int, choices=(0, 1, 2), default=1)
    parser.add_argument("--pattern", default="test_*.py")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    suite = build_suite(args.repo_root, pattern=args.pattern)
    result = unittest.TextTestRunner(verbosity=args.verbosity).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
