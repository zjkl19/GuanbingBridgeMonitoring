from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TRANSFER_SCRIPT = REPO_ROOT / "scripts" / "invoke_360disk_transfer.ps1"


class CloudDiskTransferScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        cls.node = shutil.which("node.exe") or shutil.which("node")
        bundled_node = (
            Path.home()
            / ".cache"
            / "codex-runtimes"
            / "codex-primary-runtime"
            / "dependencies"
            / "node"
            / "bin"
            / "node.exe"
        )
        if cls.node is None and bundled_node.is_file():
            cls.node = str(bundled_node)

    def test_script_contains_no_api_key_literal(self) -> None:
        source = TRANSFER_SCRIPT.read_text(encoding="utf-8-sig")
        self.assertIsNone(re.search(r"yunpan_[A-Za-z0-9_-]+", source))
        self.assertIn("NODE_USE_ENV_PROXY", source)
        self.assertIn("Never emit raw CLI output", source)

    def _run_with_fake_cli(self, action: str) -> dict[str, object]:
        if self.powershell is None or self.node is None:
            self.skipTest("PowerShell and Node are required")

        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            fake_cli = temp / "fake_360disk.js"
            fake_cli.write_text(
                """
const fs = require('fs');
const path = require('path');
const args = process.argv.slice(2);
if (args.includes('--version')) {
  process.stdout.write('0.8.37\\n');
  process.exit(0);
}
if (args.includes('download')) {
  const index = args.indexOf('--dir');
  const target = args[index + 1];
  fs.mkdirSync(target, { recursive: true });
  fs.writeFileSync(path.join(target, 'fake_download.bin'), Buffer.alloc(2048, 7));
}
process.stdout.write('{"success":true}\\n');
""".strip(),
                encoding="utf-8",
            )
            source = temp / "source.bin"
            source.write_bytes(bytes(range(256)) * 4)
            download_dir = temp / "download"

            command = [
                self.powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(TRANSFER_SCRIPT),
                "-Action",
                action,
                "-NodePath",
                self.node,
                "-CliPath",
                str(fake_cli),
                "-Attempts",
                "2",
                "-RetryDelaySeconds",
                "0",
            ]
            if action == "upload":
                command.extend(
                    [
                        "-LocalPath",
                        str(source),
                        "-RemoteDirectory",
                        "/test/",
                        "-NetworkMode",
                        "auto",
                    ]
                )
            else:
                command.extend(
                    [
                        "-Nid",
                        "123456",
                        "-DownloadDirectory",
                        str(download_dir),
                        "-NetworkMode",
                        "auto",
                    ]
                )

            environment = os.environ.copy()
            environment["API_KEY"] = "test-only-placeholder"
            environment["HTTP_PROXY"] = "http://127.0.0.1:10809"
            environment["HTTPS_PROXY"] = "http://127.0.0.1:10809"
            completed = subprocess.run(
                command,
                cwd=REPO_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            output_lines = [line for line in completed.stdout.splitlines() if line.strip()]
            self.assertTrue(output_lines, completed.stderr)
            return json.loads(output_lines[-1])

    def test_single_direct_upload_mode_remains_an_array(self) -> None:
        result = self._run_with_fake_cli("upload")
        self.assertTrue(result["success"])
        self.assertEqual("direct", result["network_mode"])
        self.assertEqual(1024, result["bytes"])
        self.assertEqual(64, len(result["sha256"]))

    def test_auto_download_prefers_configured_proxy_and_hashes_output(self) -> None:
        result = self._run_with_fake_cli("download")
        self.assertTrue(result["success"])
        self.assertEqual("proxy", result["network_mode"])
        self.assertEqual(2048, result["bytes"])
        self.assertEqual(64, len(result["sha256"]))


if __name__ == "__main__":
    unittest.main()
