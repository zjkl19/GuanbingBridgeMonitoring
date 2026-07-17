from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "scripts" / "validate_public_release_diff.ps1"
PUBLIC_ALLOWLIST = ROOT / "config" / "public_release_allowlist_v1.8.2.txt"


class PublicReleaseDiffGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        cls.git = shutil.which("git")
        if cls.powershell is None or cls.git is None:
            raise unittest.SkipTest("PowerShell and Git are required")

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "public-guard-fixture"
        self.repo.mkdir()
        self._git("init", "-b", "main")
        self._git("config", "user.name", "Public Guard Test")
        self._git("config", "user.email", "guard@example.invalid")
        (self.repo / "README.md").write_text("baseline\n", encoding="utf-8")
        self._git("add", "README.md")
        self._git("commit", "-m", "baseline")
        self.base = self._git("rev-parse", "HEAD").stdout.strip()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [self.git, "-C", str(self.repo), *args],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )

    def _write(self, relative: str, text: str) -> Path:
        path = self.repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def _allow(self, *paths: str) -> Path:
        return self._write("release.allowlist", "\n".join(paths) + "\n")

    def _make_junction(self, link: Path, target: Path) -> None:
        if os.name != "nt":
            self.skipTest("Windows junction regression requires Windows")
        completed = subprocess.run(
            ["cmd.exe", "/d", "/c", "mklink", "/J", str(link), str(target)],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if completed.returncode != 0:
            self.skipTest(f"cannot create test junction: {completed.stderr}")

    @staticmethod
    def _docx_bytes(
        footer_text: str,
        document_text: str = "document",
        footer_attributes: str = "",
    ) -> bytes:
        stream = io.BytesIO()
        members = (
            ("[Content_Types].xml", "<Types/>"),
            ("_rels/.rels", "<Relationships/>"),
            ("word/media/", ""),
            (
                "word/document.xml",
                '<w:document xmlns:w="http://schemas.openxmlformats.org/'
                f'wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>{document_text}'
                "</w:t></w:r></w:p></w:body></w:document>",
            ),
            (
                "word/footer5.xml",
                '<w:ftr xmlns:w="http://schemas.openxmlformats.org/'
                f'wordprocessingml/2006/main"><w:p><w:r><w:t{footer_attributes}>'
                f"{footer_text}"
                "</w:t></w:r></w:p></w:ftr>",
            ),
        )
        with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, text in members:
                archive.writestr(name, text.encode("utf-8"))
        return stream.getvalue()

    @staticmethod
    def _zip_total(payload: bytes) -> int:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            return sum(info.file_size for info in archive.infolist())

    @staticmethod
    def _zip_member_hash(payload: bytes, member: str) -> str:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            return hashlib.sha256(archive.read(member)).hexdigest().upper()

    def _prepare_docx_contract(
        self,
        *,
        current_footer_text: str = "PAGE SECTIONPAGES",
        current_footer_attributes: str = "",
        current_document_text: str = "document",
        mutate_current=None,
        track_contract: bool = True,
    ) -> tuple[str, Path, dict]:
        relative = "reports/管柄模板.docx"
        target = self.repo / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        baseline = self._docx_bytes("page total 28")
        target.write_bytes(baseline)
        self._git("add", relative)
        self._git("commit", "-m", "add binary baseline")
        self.base = self._git("rev-parse", "HEAD").stdout.strip()

        current = self._docx_bytes(
            current_footer_text,
            current_document_text,
            current_footer_attributes,
        )
        if mutate_current is not None:
            current = mutate_current(current)
        target.write_bytes(current)
        contract_relative = "config/public_release_binary_contract_v1.8.2.json"
        contract = {
            "schema_version": 1,
            "contracts": [
                {
                    "path": relative,
                    "kind": "docx_member_diff",
                    "base_sha256": hashlib.sha256(baseline).hexdigest().upper(),
                    "current_sha256": hashlib.sha256(current).hexdigest().upper(),
                    "member_count": 5,
                    "base_total_uncompressed_bytes": self._zip_total(baseline),
                    "current_total_uncompressed_bytes": self._zip_total(
                        self._docx_bytes(
                            current_footer_text,
                            current_document_text,
                            current_footer_attributes,
                        )
                    ),
                    "allowed_changed_members": [
                        {
                            "path": "word/footer5.xml",
                            "base_sha256": self._zip_member_hash(
                                baseline, "word/footer5.xml"
                            ),
                            "current_sha256": self._zip_member_hash(
                                self._docx_bytes(
                                    current_footer_text,
                                    current_document_text,
                                    current_footer_attributes,
                                ),
                                "word/footer5.xml",
                            ),
                        }
                    ],
                }
            ],
        }
        contract_path = self.repo / contract_relative
        contract_path.parent.mkdir(parents=True, exist_ok=True)
        contract_path.write_text(
            json.dumps(contract, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        if track_contract:
            self._git("add", contract_relative)
        return relative, contract_path, contract

    def _run(
        self, allowlist: Path, *, binary_contract_path: Path | None = None
    ) -> tuple[subprocess.CompletedProcess[str], dict]:
        command = [
            self.powershell,
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(GUARD),
            "-BaseRef",
            self.base,
            "-AllowlistPath",
            str(allowlist),
            "-RepositoryRoot",
            str(self.repo),
        ]
        if binary_contract_path is not None:
            command.extend(("-BinaryContractPath", str(binary_contract_path)))
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8-sig",
        )
        payload = json.loads(completed.stdout.strip())
        return completed, payload

    def test_exact_safe_diff_passes_and_does_not_mutate_repository(self) -> None:
        safe_address = ".".join(("192", "0", "2", "44"))
        self._write("src/feature.txt", f"documentation endpoint {safe_address}\n")
        allowlist = self._allow("release.allowlist", "src/feature.txt")
        before_status = self._git("status", "--porcelain=v1", "--untracked-files=all").stdout
        before_head = self._git("rev-parse", "HEAD").stdout

        completed, payload = self._run(allowlist)

        after_status = self._git("status", "--porcelain=v1", "--untracked-files=all").stdout
        after_head = self._git("rev-parse", "HEAD").stdout
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(payload["status"], "ok")
        self.assertTrue(payload["read_only"])
        self.assertEqual(
            payload["changed_files"], ["release.allowlist", "src/feature.txt"]
        )
        self.assertEqual(payload["sensitive_findings"], [])
        self.assertEqual(after_status, before_status)
        self.assertEqual(after_head, before_head)

    def test_changed_file_set_must_match_allowlist_exactly(self) -> None:
        self._write("src/expected.txt", "safe\n")
        self._write("src/unexpected.txt", "also safe\n")
        allowlist = self._allow("release.allowlist", "src/expected.txt", "src/missing.txt")

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2)
        self.assertEqual(payload["status"], "failed")
        self.assertEqual(payload["missing_files"], ["src/missing.txt"])
        self.assertEqual(payload["unexpected_files"], ["src/unexpected.txt"])

    def test_chinese_docx_path_passes_only_with_exact_member_contract(self) -> None:
        relative, contract_path, _contract = self._prepare_docx_contract()
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 0, payload)
        self.assertEqual(payload["status"], "ok")
        self.assertIn(relative, payload["changed_files"])
        self.assertNotIn('"', relative)
        self.assertEqual(
            payload["binary_contract_results"],
            [
                {
                    "path": relative,
                    "kind": "docx_member_diff",
                    "status": "ok",
                    "errors": [],
                    "member_count": 5,
                    "changed_members": ["word/footer5.xml"],
                }
            ],
        )
        self.assertEqual(payload["sensitive_findings"], [])
        self.assertEqual(contract_path.name, payload["binary_contract_name"])

    def test_docx_contract_must_resolve_inside_repository(self) -> None:
        relative, contract_path, _contract = self._prepare_docx_contract()
        external_contract = Path(self.temp.name) / "external-contract.json"
        shutil.copyfile(contract_path, external_contract)
        allowlist = self._allow("release.allowlist", relative)

        completed, payload = self._run(
            allowlist, binary_contract_path=external_contract
        )

        self.assertEqual(completed.returncode, 3, payload)
        self.assertEqual(payload["status"], "error")
        self.assertIn("inside the repository root", payload["error"])

    def test_docx_contract_file_must_be_exactly_allowlisted(self) -> None:
        relative, _contract_path, _contract = self._prepare_docx_contract()
        allowlist = self._allow("release.allowlist", relative)

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 3, payload)
        self.assertEqual(payload["status"], "error")
        self.assertIn("must also be present", payload["error"])

    def test_docx_contract_must_be_git_tracked(self) -> None:
        relative, _contract_path, _contract = self._prepare_docx_contract(
            track_contract=False
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 3, payload)
        self.assertEqual(payload["status"], "error")
        self.assertIn("ls-files", payload["error"])

    def test_docx_contract_path_rejects_intermediate_junction(self) -> None:
        relative, contract_path, _contract = self._prepare_docx_contract()
        alias = self.repo / "contract-alias"
        self._make_junction(alias, contract_path.parent)
        try:
            allowlist = self._allow("release.allowlist", relative)
            completed, payload = self._run(
                allowlist, binary_contract_path=alias / contract_path.name
            )
        finally:
            os.rmdir(alias)

        self.assertEqual(completed.returncode, 3, payload)
        self.assertEqual(payload["status"], "error")
        self.assertIn("cannot traverse a reparse point", payload["error"])

    def test_docx_contract_target_rejects_intermediate_junction(self) -> None:
        relative, _contract_path, _contract = self._prepare_docx_contract()
        reports = self.repo / "reports"
        real_reports = self.repo / "reports-real"
        reports.rename(real_reports)
        self._make_junction(reports, real_reports)
        try:
            allowlist = self._allow(
                "release.allowlist",
                "config/public_release_binary_contract_v1.8.2.json",
                relative,
            )
            completed, payload = self._run(allowlist)
        finally:
            os.rmdir(reports)
            real_reports.rename(reports)

        self.assertEqual(completed.returncode, 3, payload)
        self.assertEqual(payload["status"], "error")
        self.assertIn("cannot traverse a reparse point", payload["error"])

    def test_docx_contract_scans_xml_entity_decoded_dom_values(self) -> None:
        entity_path = "C&#58;&#92;Users&#92;operator&#92;secret.txt"
        relative, _contract_path, _contract = self._prepare_docx_contract(
            current_footer_text=entity_path
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertIn(
            "changed_member_sensitive_content",
            payload["binary_contract_results"][0]["errors"],
        )
        self.assertTrue(
            any(
                finding["kind"] == "absolute_windows_path"
                and finding["path"].endswith("#decoded")
                for finding in payload["sensitive_findings"]
            ),
            payload["sensitive_findings"],
        )
        self.assertNotIn(
            chr(67) + ":" + chr(92) + chr(92).join(
                ("Users", "operator", "secret.txt")
            ),
            json.dumps(payload, ensure_ascii=False),
        )

    def test_docx_contract_scans_xml_entity_decoded_attributes(self) -> None:
        entity_path = "C&#58;&#92;Users&#92;operator&#92;attribute.txt"
        relative, _contract_path, _contract = self._prepare_docx_contract(
            current_footer_attributes=f' data-path="{entity_path}"'
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertIn(
            "changed_member_sensitive_content",
            payload["binary_contract_results"][0]["errors"],
        )
        self.assertTrue(
            any(
                finding["kind"] == "absolute_windows_path"
                and finding["path"].endswith("#decoded")
                for finding in payload["sensitive_findings"]
            ),
            payload["sensitive_findings"],
        )

    def test_docx_contract_scans_path_split_across_word_runs(self) -> None:
        slash = chr(92)
        split_path = (
            chr(67)
            + ":"
            + slash
            + "Us</w:t></w:r><w:r><w:t>ers"
            + slash
            + "operator"
            + slash
            + "split-run.txt"
        )
        relative, _contract_path, _contract = self._prepare_docx_contract(
            current_footer_text=split_path
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertTrue(
            any(
                finding["kind"] == "absolute_windows_path"
                and finding["path"].endswith("#decoded-paragraph")
                for finding in payload["sensitive_findings"]
            ),
            payload["sensitive_findings"],
        )

    def test_docx_contract_scans_path_split_across_paragraphs(self) -> None:
        slash = chr(92)
        split_path = (
            chr(67)
            + ":"
            + slash
            + "Us</w:t></w:r></w:p><w:p><w:r><w:t>ers"
            + slash
            + "operator"
            + slash
            + "split-paragraph.txt"
        )
        relative, _contract_path, _contract = self._prepare_docx_contract(
            current_footer_text=split_path
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertTrue(
            any(
                finding["kind"] == "absolute_windows_path"
                and finding["path"].endswith("#decoded-document")
                for finding in payload["sensitive_findings"]
            ),
            payload["sensitive_findings"],
        )

    def test_docx_contract_rejects_dtd(self) -> None:
        def add_doctype(payload: bytes) -> bytes:
            source = io.BytesIO(payload)
            target = io.BytesIO()
            with zipfile.ZipFile(source) as source_zip, zipfile.ZipFile(
                target, "w", compression=zipfile.ZIP_DEFLATED
            ) as target_zip:
                for info in source_zip.infolist():
                    member = source_zip.read(info.filename)
                    if info.filename == "word/footer5.xml":
                        member = b"<!DOCTYPE w:ftr>" + member
                    target_zip.writestr(info, member)
            return target.getvalue()

        relative, _contract_path, _contract = self._prepare_docx_contract(
            mutate_current=add_doctype
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertIn(
            "changed_member_xml_invalid",
            payload["binary_contract_results"][0]["errors"],
        )

    def test_docx_contract_rejects_excessive_xml_characters(self) -> None:
        relative, _contract_path, _contract = self._prepare_docx_contract(
            current_footer_text="x" * (8 * 1024 * 1024 + 1)
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertIn(
            "changed_member_xml_character_limit_exceeded",
            payload["binary_contract_results"][0]["errors"],
        )

    def test_docx_contract_rejects_an_additional_changed_member(self) -> None:
        relative, _contract_path, _contract = self._prepare_docx_contract(
            current_document_text="unexpected document change"
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        result = payload["binary_contract_results"][0]
        self.assertEqual(result["status"], "failed")
        self.assertIn("changed_members_mismatch", result["errors"])
        self.assertEqual(
            set(result["changed_members"]),
            {"word/document.xml", "word/footer5.xml"},
        )
        self.assertIn(
            "binary_contract_violation",
            {finding["kind"] for finding in payload["sensitive_findings"]},
        )

    def test_docx_contract_rejects_encrypted_zip_flag(self) -> None:
        def set_encryption_flag(payload: bytes) -> bytes:
            patched = bytearray(payload)
            local = patched.find(b"PK\x03\x04")
            central = patched.find(b"PK\x01\x02")
            self.assertGreaterEqual(local, 0)
            self.assertGreaterEqual(central, 0)
            patched[local + 6] |= 1
            patched[central + 8] |= 1
            return bytes(patched)

        relative, _contract_path, _contract = self._prepare_docx_contract(
            mutate_current=set_encryption_flag
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertIn(
            "zip_encrypted_entry_not_allowed",
            payload["binary_contract_results"][0]["errors"],
        )

    def test_docx_contract_rejects_crc_mismatch(self) -> None:
        def corrupt_central_crc(payload: bytes) -> bytes:
            patched = bytearray(payload)
            central = patched.find(b"PK\x01\x02")
            self.assertGreaterEqual(central, 0)
            patched[central + 16] ^= 0xFF
            return bytes(patched)

        relative, _contract_path, _contract = self._prepare_docx_contract(
            mutate_current=corrupt_central_crc
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertIn(
            "zip_member_crc_mismatch",
            payload["binary_contract_results"][0]["errors"],
        )

    def test_docx_contract_rejects_unsafe_member_path(self) -> None:
        def replace_central_name(payload: bytes) -> bytes:
            patched = bytearray(payload)
            name = b"word/footer5.xml"
            replacement = b"../escape000.xml"
            self.assertEqual(len(name), len(replacement))
            central_name = patched.find(name, patched.find(b"PK\x01\x02"))
            self.assertGreaterEqual(central_name, 0)
            patched[central_name : central_name + len(name)] = replacement
            return bytes(patched)

        relative, _contract_path, _contract = self._prepare_docx_contract(
            mutate_current=replace_central_name
        )
        allowlist = self._allow(
            "release.allowlist",
            "config/public_release_binary_contract_v1.8.2.json",
            relative,
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertIn(
            "zip_member_path_unsafe",
            payload["binary_contract_results"][0]["errors"],
        )

    def test_internal_state_path_is_forbidden_even_when_allowlisted(self) -> None:
        internal = "docs/ops/status.md"
        self._write(internal, "generic state\n")
        allowlist = self._allow("release.allowlist", internal)

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2)
        self.assertEqual(payload["forbidden_files"], [internal])

    def test_uncontracted_binary_remains_rejected_when_allowlisted(self) -> None:
        binary = self.repo / "assets" / "uncontracted.bin"
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_bytes(b"\x00baseline")
        self._git("add", "assets/uncontracted.bin")
        self._git("commit", "-m", "add binary baseline")
        self.base = self._git("rev-parse", "HEAD").stdout.strip()
        binary.write_bytes(b"\x00current")
        allowlist = self._allow("release.allowlist", "assets/uncontracted.bin")

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2, payload)
        self.assertTrue(
            any(
                finding["path"] == "assets/uncontracted.bin"
                and finding["kind"] == "binary_diff_unscanned"
                for finding in payload["sensitive_findings"]
            ),
            payload["sensitive_findings"],
        )

    def test_sensitive_added_lines_are_classified_without_echoing_values(self) -> None:
        private_address = ".".join(("192", str(160 + 8), "77", "31"))
        drive_path = chr(67) + ":\\" + "Users\\operator\\artifact.json"
        ssh_target = "ssh " + "operator@" + "host.internal"
        task_state = "scheduled " + "task sample is " + "running pid " + "42"
        fake_key = "api_" + "key = " + "ghp_" + ("A" * 40)
        text = "\n".join(
            (private_address, drive_path, ssh_target, task_state, fake_key, "")
        )
        self._write("src/sensitive.txt", text)
        allowlist = self._allow("release.allowlist", "src/sensitive.txt")

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2)
        kinds = {finding["kind"] for finding in payload["sensitive_findings"]}
        self.assertTrue(
            {
                "rfc1918_ip",
                "absolute_windows_path",
                "ssh_user_target",
                "scheduled_task_status",
                "credential_token",
                "credential_assignment",
            }.issubset(kinds),
            kinds,
        )
        serialized = json.dumps(payload, ensure_ascii=False)
        self.assertNotIn(private_address, serialized)
        self.assertNotIn(drive_path, serialized)
        self.assertNotIn(ssh_target, serialized)
        self.assertNotIn("ghp_", serialized)

    def test_tracked_file_added_lines_are_scanned(self) -> None:
        private_address = ".".join(("10", "23", "45", "67"))
        (self.repo / "README.md").write_text(
            f"baseline\ninternal endpoint {private_address}\n", encoding="utf-8"
        )
        allowlist = self._allow("README.md", "release.allowlist")

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 2)
        findings = payload["sensitive_findings"]
        self.assertTrue(
            any(
                item["path"] == "README.md"
                and item["line"] == 2
                and item["kind"] == "rfc1918_ip"
                for item in findings
            ),
            findings,
        )
        self.assertNotIn(private_address, json.dumps(payload, ensure_ascii=False))

    def test_duplicate_or_non_exact_allowlist_entry_is_configuration_error(self) -> None:
        self._write("src/feature.txt", "safe\n")
        allowlist = self._write(
            "release.allowlist", "src/*.txt\nsrc/*.txt\n"
        )

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 3)
        self.assertEqual(payload["status"], "error")
        self.assertIn("exact repository-relative paths", payload["error"])

    def test_guard_sources_do_not_trigger_their_own_sensitive_patterns(self) -> None:
        copied = (
            "scripts/validate_public_release_diff.ps1",
            "tests_py/test_public_release_diff_guard.py",
            "config/public_release_allowlist_v1.8.2.txt",
        )
        sources = (GUARD, Path(__file__), PUBLIC_ALLOWLIST)
        for relative, source in zip(copied, sources, strict=True):
            destination = self.repo / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        allowlist = self._allow("release.allowlist", *copied)

        completed, payload = self._run(allowlist)

        self.assertEqual(completed.returncode, 0, payload)
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["sensitive_findings"], [])


if __name__ == "__main__":
    unittest.main()
