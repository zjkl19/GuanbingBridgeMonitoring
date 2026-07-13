from __future__ import annotations

import hashlib
import json
import os
import re
import re
import shutil
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Callable, Iterable


GITHUB_API_VERSION = "2022-11-28"
DEFAULT_REPOSITORY = "zjkl19/GuanbingBridgeMonitoring"
VERSION_PATTERN = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$")


class UpdateError(RuntimeError):
    pass


class NoReleaseAvailable(UpdateError):
    pass


class UpdateSecurityError(UpdateError):
    pass


@dataclass(frozen=True)
class UpdatePolicy:
    repository: str = DEFAULT_REPOSITORY
    channel: str = "stable"
    auto_check: bool = True
    check_interval_hours: int = 24
    startup_delay_seconds: int = 5
    package_prefix: str = "BridgeMonitoringWorkbench-"
    package_suffix: str = "-win-x64.zip"

    @classmethod
    def load(cls, project_root: Path) -> "UpdatePolicy":
        path = project_root / "config" / "workbench_update.json"
        if not path.is_file():
            return cls()
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(payload, dict):
            raise UpdateError(f"更新策略必须是 JSON 对象：{path}")
        return cls(
            repository=str(payload.get("repository") or DEFAULT_REPOSITORY),
            channel=str(payload.get("channel") or "stable"),
            auto_check=bool(payload.get("auto_check", True)),
            check_interval_hours=max(1, int(payload.get("check_interval_hours", 24))),
            startup_delay_seconds=max(0, int(payload.get("startup_delay_seconds", 5))),
            package_prefix=str(payload.get("package_prefix") or "BridgeMonitoringWorkbench-"),
            package_suffix=str(payload.get("package_suffix") or "-win-x64.zip"),
        )


@dataclass(frozen=True)
class ReleaseAsset:
    name: str
    download_url: str
    size: int
    digest: str = ""


@dataclass(frozen=True)
class UpdateInfo:
    current_version: str
    latest_version: str
    release_name: str
    release_notes: str
    html_url: str
    published_at: str
    package_asset: ReleaseAsset | None
    checksum_asset: ReleaseAsset | None

    @property
    def update_available(self) -> bool:
        return is_newer_version(self.current_version, self.latest_version)

    @property
    def installable(self) -> bool:
        return self.package_asset is not None and (
            bool(self.package_asset.digest) or self.checksum_asset is not None
        )


@dataclass(frozen=True)
class StagedUpdate:
    version: str
    archive_path: Path
    package_root: Path
    executable_path: Path
    manifest_path: Path
    archive_sha256: str


@dataclass(frozen=True)
class InstalledUpdate:
    version: str
    install_root: Path
    backup_root: Path
    log_path: Path


@dataclass(frozen=True)
class UpdateBackup:
    path: Path
    version: str
    replaced_by_version: str
    created_at: str
    safe_to_remove: bool
    issue: str = ""


REQUIRED_RELEASE_GATES = (
    "includes_analysis_runner",
    "auto_threshold_preview_runner_smoke",
    "installed_profile_matrix_smoke",
    "invalid_cli_smoke",
    "includes_report_builder",
    "report_builder_context_smoke",
    "embedded_report_job_smoke",
    "report_gate_contract_smoke",
    "report_visual_qc_smoke",
)


def discover_update_backups(install_root: Path) -> tuple[UpdateBackup, ...]:
    install_root = install_root.expanduser().resolve()
    parent = install_root.parent
    name = re.escape(install_root.name)
    pattern = re.compile(
        rf"^{name}\.backup_(?P<version>v\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?)_"
        r"(?P<stamp>\d{8}_\d{6})(?:_[0-9a-fA-F]{8})?$"
    )
    backups: list[UpdateBackup] = []
    for candidate in parent.iterdir():
        match = pattern.fullmatch(candidate.name)
        if match is None or not candidate.is_dir() or candidate.is_symlink():
            continue
        resolved = candidate.resolve()
        if resolved.parent != parent:
            continue
        replaced_by_version = match.group("version")
        issue = ""
        manifest_path = resolved / "release_manifest.json"
        executable_path = resolved / "BridgeMonitoringWorkbench.exe"
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
            manifest_version = str(manifest.get("version") or "") if isinstance(manifest, dict) else ""
        except (OSError, json.JSONDecodeError):
            manifest_version = ""
        if not executable_path.is_file():
            issue = "缺少工作台 EXE"
        elif not manifest_version:
            issue = "缺少可读取的发布清单"
        else:
            try:
                _version_tuple(manifest_version)
            except UpdateError:
                issue = f"发布清单版本无效（{manifest_version}）"
        backups.append(
            UpdateBackup(
                path=resolved,
                version=manifest_version or "未知",
                replaced_by_version=replaced_by_version,
                created_at=match.group("stamp"),
                safe_to_remove=not issue,
                issue=issue,
            )
        )
    return tuple(sorted(backups, key=lambda item: (item.created_at, item.path.name), reverse=True))


def cleanup_update_backups(install_root: Path, *, keep_latest: int = 2) -> tuple[UpdateBackup, ...]:
    if keep_latest < 1:
        raise UpdateError("更新备份至少保留 1 个")
    install_root = install_root.expanduser().resolve()
    eligible = [item for item in discover_update_backups(install_root) if item.safe_to_remove]
    removed: list[UpdateBackup] = []
    for item in eligible[keep_latest:]:
        # Re-discover immediately before each destructive operation. This keeps
        # deletion limited to a direct, recognized sibling of the live install.
        current = {entry.path: entry for entry in discover_update_backups(install_root)}.get(item.path)
        if current is None or not current.safe_to_remove or current.path.parent != install_root.parent:
            raise UpdateSecurityError(f"更新备份身份在清理前发生变化：{item.path}")
        shutil.rmtree(current.path)
        removed.append(current)
    return tuple(removed)
LEGACY_MANAGED_DIRECTORIES = ("_internal", "bin", "reporting", "reports")
LEGACY_MANAGED_FILES = (
    "BridgeMonitoringWorkbench.exe",
    "README.md",
    "VERSION",
    "release_manifest.json",
    "workbench_smoke.json",
    "workbench_profile_matrix.json",
    "workbench_startup.png",
    "workbench_alarm_editor.png",
    "workbench_warning_overview.png",
    "workbench_cleaning_editor.png",
    "workbench_post_filter_editor.png",
    "workbench_auto_threshold.png",
    "workbench_offset_editor.png",
    "workbench_group_plot_editor.png",
    "workbench_plot_common_editor.png",
    "workbench_spectrum_editor.png",
    "workbench_report_task.png",
)


def _version_tuple(value: str) -> tuple[int, int, int]:
    match = VERSION_PATTERN.fullmatch(value.strip())
    if not match:
        raise UpdateError(f"不支持的版本格式：{value!r}")
    return tuple(int(item) for item in match.groups())  # type: ignore[return-value]


def is_newer_version(current: str, latest: str) -> bool:
    return _version_tuple(latest) > _version_tuple(current)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _asset_from_payload(raw: dict[str, Any]) -> ReleaseAsset:
    return ReleaseAsset(
        name=str(raw.get("name") or ""),
        download_url=str(raw.get("browser_download_url") or ""),
        size=int(raw.get("size") or 0),
        digest=str(raw.get("digest") or ""),
    )


class GitHubReleaseClient:
    def __init__(
        self,
        policy: UpdatePolicy,
        *,
        opener: Callable[..., Any] = urllib.request.urlopen,
        timeout: int = 20,
    ) -> None:
        self.policy = policy
        self._opener = opener
        self.timeout = timeout

    @staticmethod
    def _request(url: str) -> urllib.request.Request:
        return urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": GITHUB_API_VERSION,
                "User-Agent": "Guanbing-Bridge-Monitoring-Workbench",
            },
        )

    def latest_release(self, current_version: str) -> UpdateInfo:
        url = f"https://api.github.com/repos/{self.policy.repository}/releases/latest"
        try:
            with self._opener(self._request(url), timeout=self.timeout) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise NoReleaseAvailable("GitHub 尚未发布正式 Release") from exc
            raise UpdateError(f"GitHub Release 查询失败：HTTP {exc.code}") from exc
        except (OSError, ValueError) as exc:
            raise UpdateError(f"GitHub Release 查询失败：{exc}") from exc
        if not isinstance(payload, dict):
            raise UpdateError("GitHub Release 响应格式无效")
        latest = str(payload.get("tag_name") or "")
        _version_tuple(latest)
        assets = [_asset_from_payload(item) for item in payload.get("assets", []) if isinstance(item, dict)]
        expected_package_name = f"{self.policy.package_prefix}{latest}{self.policy.package_suffix}"
        package = next((item for item in assets if item.name == expected_package_name), None)
        checksum = None
        if package is not None:
            expected_name = f"{package.name}.sha256"
            checksum = next((item for item in assets if item.name == expected_name), None)
        return UpdateInfo(
            current_version=current_version,
            latest_version=latest,
            release_name=str(payload.get("name") or latest),
            release_notes=str(payload.get("body") or ""),
            html_url=str(payload.get("html_url") or ""),
            published_at=str(payload.get("published_at") or ""),
            package_asset=package,
            checksum_asset=checksum,
        )

    def _download_asset(
        self,
        asset: ReleaseAsset,
        target: Path,
        progress: Callable[[int, int], None] | None = None,
    ) -> Path:
        target.parent.mkdir(parents=True, exist_ok=True)
        request = self._request(asset.download_url)
        try:
            with self._opener(request, timeout=max(self.timeout, 60)) as response, target.open("wb") as stream:
                total = int(response.headers.get("Content-Length") or asset.size or 0)
                received = 0
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    stream.write(chunk)
                    received += len(chunk)
                    if progress:
                        progress(received, total)
        except OSError as exc:
            target.unlink(missing_ok=True)
            raise UpdateError(f"更新资产下载失败：{exc}") from exc
        if asset.size and target.stat().st_size != asset.size:
            target.unlink(missing_ok=True)
            raise UpdateSecurityError("更新资产大小与 GitHub Release 记录不一致")
        return target

    def download_verified_package(
        self,
        info: UpdateInfo,
        target_dir: Path,
        progress: Callable[[int, int], None] | None = None,
    ) -> tuple[Path, str]:
        asset = info.package_asset
        if asset is None:
            raise UpdateError("GitHub Release 未包含 Windows x64 工作台 ZIP")
        archive = self._download_asset(asset, target_dir / asset.name, progress)
        expected = ""
        if asset.digest.lower().startswith("sha256:"):
            expected = asset.digest.split(":", 1)[1].strip().lower()
        elif info.checksum_asset is not None:
            checksum_path = self._download_asset(
                info.checksum_asset,
                target_dir / info.checksum_asset.name,
            )
            checksum_text = checksum_path.read_text(encoding="utf-8-sig").strip()
            expected = checksum_text.split()[0].lower() if checksum_text else ""
        if not re.fullmatch(r"[0-9a-f]{64}", expected):
            archive.unlink(missing_ok=True)
            raise UpdateSecurityError("Release 缺少有效 SHA256，拒绝安装")
        actual = file_sha256(archive)
        if actual != expected:
            archive.unlink(missing_ok=True)
            raise UpdateSecurityError(f"更新 ZIP 的 SHA256 校验失败：expected={expected}, actual={actual}")
        return archive, actual


def _safe_zip_members(archive: zipfile.ZipFile) -> Iterable[zipfile.ZipInfo]:
    seen: set[str] = set()
    for member in archive.infolist():
        normalized = member.filename.replace("\\", "/")
        path = PurePosixPath(normalized)
        if (
            path.is_absolute()
            or ".." in path.parts
            or normalized.startswith("//")
            or re.match(r"^[A-Za-z]:", normalized)
        ):
            raise UpdateSecurityError(f"更新 ZIP 含不安全路径：{member.filename}")
        key = normalized.rstrip("/").casefold()
        if not key:
            raise UpdateSecurityError("update ZIP contains an empty member path")
        if key in seen:
            raise UpdateSecurityError(f"update ZIP contains a duplicate path: {member.filename}")
        seen.add(key)
        unix_mode = (member.external_attr >> 16) & 0xFFFF
        if stat.S_ISLNK(unix_mode):
            raise UpdateSecurityError(f"update ZIP contains a symbolic link: {member.filename}")
        yield member


def _safe_relative_path(value: object) -> Path:
    normalized = str(value or "").replace("\\", "/")
    pure = PurePosixPath(normalized)
    if (
        not normalized
        or pure.is_absolute()
        or ".." in pure.parts
        or normalized.startswith("//")
        or re.match(r"^[A-Za-z]:", normalized)
    ):
        raise UpdateSecurityError(f"release manifest contains unsafe file path: {value!r}")
    return Path(*pure.parts)


def _release_inventory(payload: dict[str, Any]) -> tuple[tuple[Path, int, str], ...]:
    if int(payload.get("schema_version") or 0) < 2:
        raise UpdateSecurityError("release manifest schema_version must be at least 2")
    raw_inventory = payload.get("file_inventory")
    if not isinstance(raw_inventory, list) or not raw_inventory:
        raise UpdateSecurityError("release manifest is missing the complete file inventory")
    records: list[tuple[Path, int, str]] = []
    seen: set[str] = set()
    for index, raw in enumerate(raw_inventory, start=1):
        if not isinstance(raw, dict):
            raise UpdateSecurityError(f"release inventory row {index} must be an object")
        relative = _safe_relative_path(raw.get("path"))
        normalized = relative.as_posix().casefold()
        if normalized == "release_manifest.json":
            raise UpdateSecurityError("release manifest cannot inventory itself")
        if normalized in seen:
            raise UpdateSecurityError(f"duplicate release inventory path: {relative.as_posix()}")
        seen.add(normalized)
        try:
            size = int(raw.get("bytes"))
        except (TypeError, ValueError) as exc:
            raise UpdateSecurityError(f"invalid release inventory size: {relative.as_posix()}") from exc
        digest = str(raw.get("sha256") or "").lower()
        if size < 0 or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise UpdateSecurityError(f"invalid release inventory record: {relative.as_posix()}")
        records.append((relative, size, digest))
    declared_count = int(payload.get("file_inventory_count") or len(records))
    if declared_count != len(records):
        raise UpdateSecurityError("release inventory count does not close")
    return tuple(records)


def validate_release_package(
    package_root: Path,
    *,
    expected_version: str | None = None,
    allow_config_overrides: bool = False,
    allow_extra_files: bool = False,
) -> dict[str, Any]:
    package_root = package_root.resolve()
    manifest_path = package_root / "release_manifest.json"
    if not manifest_path.is_file():
        raise UpdateSecurityError("update package is missing release_manifest.json")
    payload = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise UpdateSecurityError("release manifest root must be an object")
    version = str(payload.get("version") or "")
    _version_tuple(version)
    if expected_version is not None and _version_tuple(version) != _version_tuple(expected_version):
        raise UpdateSecurityError("update package version differs from the selected release")
    for gate in REQUIRED_RELEASE_GATES:
        if payload.get(gate) is not True:
            raise UpdateSecurityError(f"update package did not pass required release gate: {gate}")
    smoke = payload.get("smoke")
    if not isinstance(smoke, dict) or smoke.get("ok") is not True:
        raise UpdateSecurityError("update package workbench smoke gate is not successful")
    inventory = _release_inventory(payload)
    expected_paths: set[str] = set()
    for relative, size, digest in inventory:
        normalized = relative.as_posix().casefold()
        expected_paths.add(normalized)
        target = package_root / relative
        if not target.is_file():
            raise UpdateSecurityError(f"release inventory file is missing: {relative.as_posix()}")
        if allow_config_overrides and relative.parts and relative.parts[0].casefold() == "config":
            continue
        if target.stat().st_size != size:
            raise UpdateSecurityError(f"release inventory size mismatch: {relative.as_posix()}")
        if file_sha256(target) != digest:
            raise UpdateSecurityError(f"release inventory SHA256 mismatch: {relative.as_posix()}")
    if not allow_extra_files:
        actual_paths = {
            path.relative_to(package_root).as_posix().casefold()
            for path in package_root.rglob("*")
            if path.is_file()
            and path.relative_to(package_root).as_posix().casefold() != "release_manifest.json"
        }
        if actual_paths != expected_paths:
            missing = sorted(expected_paths - actual_paths)
            extra = sorted(actual_paths - expected_paths)
            raise UpdateSecurityError(
                f"release inventory file set differs: missing={missing[:5]}, extra={extra[:5]}"
            )
    executable = package_root / "BridgeMonitoringWorkbench.exe"
    expected_exe = str(payload.get("executable_sha256") or "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_exe):
        raise UpdateSecurityError("release manifest is missing a valid EXE SHA256")
    if not executable.is_file() or file_sha256(executable) != expected_exe:
        raise UpdateSecurityError("workbench EXE SHA256 differs from the release manifest")
    return payload


def stage_verified_update(
    archive_path: Path,
    version: str,
    archive_sha256: str,
    staging_parent: Path,
) -> StagedUpdate:
    token = uuid.uuid4().hex[:8]
    stage = staging_parent / token
    try:
        with zipfile.ZipFile(archive_path) as archive:
            members = list(_safe_zip_members(archive))
            if not members:
                raise UpdateSecurityError("update ZIP is empty")
            longest = max(len(str(stage.resolve() / Path(*PurePosixPath(
                member.filename.replace("\\", "/")
            ).parts))) for member in members)
            if os.name == "nt" and longest >= 240:
                stage = Path(tempfile.gettempdir()) / "bmw_stage" / token
            stage.mkdir(parents=True, exist_ok=False)
            archive.extractall(stage, members=members)
        executables = list(stage.rglob("BridgeMonitoringWorkbench.exe"))
        if len(executables) != 1:
            raise UpdateSecurityError("更新包必须且只能包含一个 BridgeMonitoringWorkbench.exe")
        executable = executables[0]
        package_root = executable.parent
        manifest = package_root / "release_manifest.json"
        if not manifest.is_file():
            raise UpdateSecurityError("更新包缺少 release_manifest.json")
        payload = json.loads(manifest.read_text(encoding="utf-8-sig"))
        if _version_tuple(str(payload.get("version") or "")) != _version_tuple(version):
            raise UpdateSecurityError("更新包内部版本与 GitHub Release 标签不一致")
        expected_exe = str(payload.get("executable_sha256") or "").lower()
        if not re.fullmatch(r"[0-9a-f]{64}", expected_exe):
            raise UpdateSecurityError("更新包清单缺少有效 EXE SHA256")
        if file_sha256(executable) != expected_exe:
            raise UpdateSecurityError("更新包 EXE SHA256 与内部清单不一致")
        validate_release_package(package_root, expected_version=version)
        return StagedUpdate(version, archive_path, package_root, executable, manifest, archive_sha256)
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def default_update_root() -> Path:
    local = os.environ.get("LOCALAPPDATA")
    return Path(local or tempfile.gettempdir()) / "BridgeMonitoringWorkbench" / "updates"


def _wait_for_process_exit(pid: int, timeout_seconds: int = 120) -> None:
    if pid <= 0 or pid == os.getpid():
        return
    deadline = time.monotonic() + max(0, timeout_seconds)
    if os.name == "nt":
        import ctypes

        synchronize = 0x00100000
        handle = ctypes.windll.kernel32.OpenProcess(synchronize, False, pid)
        if not handle:
            return
        try:
            remaining = max(0, round((deadline - time.monotonic()) * 1000))
            result = ctypes.windll.kernel32.WaitForSingleObject(handle, remaining)
            if result == 0x00000102:
                raise UpdateError(f"timed out waiting for workbench process {pid} to exit")
        finally:
            ctypes.windll.kernel32.CloseHandle(handle)
        return
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(0.1)
    raise UpdateError(f"timed out waiting for workbench process {pid} to exit")


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _remove_managed_runtime(candidate: Path) -> None:
    manifest_path = candidate / "release_manifest.json"
    removed_from_inventory = False
    if manifest_path.is_file():
        try:
            payload = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
            for relative, _size, _digest in _release_inventory(payload):
                if relative.parts and relative.parts[0].casefold() == "config":
                    continue
                target = candidate / relative
                if target.is_file() or target.is_symlink():
                    target.unlink(missing_ok=True)
            removed_from_inventory = True
        except (OSError, ValueError, UpdateSecurityError, json.JSONDecodeError):
            removed_from_inventory = False
    if not removed_from_inventory:
        for name in LEGACY_MANAGED_DIRECTORIES:
            shutil.rmtree(candidate / name, ignore_errors=True)
        for name in LEGACY_MANAGED_FILES:
            (candidate / name).unlink(missing_ok=True)
    (candidate / "release_manifest.json").unlink(missing_ok=True)


def _copy_package_into_candidate(source: Path, candidate: Path) -> None:
    for item in source.iterdir():
        target = candidate / item.name
        if item.name.casefold() == "config":
            target.mkdir(parents=True, exist_ok=True)
            for config_file in item.rglob("*"):
                if not config_file.is_file():
                    continue
                relative = config_file.relative_to(item)
                destination = target / relative
                if not destination.exists():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(config_file, destination)
        elif item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)


def install_staged_update(
    source_root: Path,
    install_root: Path,
    version: str,
    *,
    wait_pid: int = 0,
    restart: bool = True,
    timeout_seconds: int = 120,
    log_path: Path | None = None,
    failure_point: str = "",
) -> InstalledUpdate:
    source_root = source_root.resolve()
    install_root = install_root.resolve()
    if source_root == install_root or _is_relative_to(source_root, install_root) or _is_relative_to(install_root, source_root):
        raise UpdateSecurityError("staged package and install directory must be separate")
    if not (install_root / "BridgeMonitoringWorkbench.exe").is_file():
        raise UpdateSecurityError(f"install directory has no workbench EXE: {install_root}")
    validate_release_package(source_root, expected_version=version)
    _wait_for_process_exit(wait_pid, timeout_seconds)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    nonce = uuid.uuid4().hex[:8]
    pending = install_root.with_name(f"{install_root.name}.pending_{version}_{nonce}")
    backup = install_root.with_name(f"{install_root.name}.backup_{version}_{stamp}_{nonce}")
    log = (log_path or install_root.with_name(f"{install_root.name}.update_{version}_{stamp}_{nonce}.json")).resolve()
    swapped = False
    activated = False
    try:
        shutil.copytree(install_root, pending)
        _remove_managed_runtime(pending)
        _copy_package_into_candidate(source_root, pending)
        validate_release_package(
            pending,
            expected_version=version,
            allow_config_overrides=True,
            allow_extra_files=True,
        )
        if failure_point == "after_candidate_validation":
            raise UpdateError("injected failure after candidate validation")
        install_root.rename(backup)
        swapped = True
        if failure_point == "after_backup_rename":
            raise UpdateError("injected failure after backup rename")
        pending.rename(install_root)
        swapped = False
        activated = True
        if failure_point == "after_activation":
            raise UpdateError("injected failure after activation")
        validate_release_package(
            install_root,
            expected_version=version,
            allow_config_overrides=True,
            allow_extra_files=True,
        )
        payload = {
            "status": "installed",
            "version": version,
            "install_root": str(install_root),
            "backup_root": str(backup),
            "source_root": str(source_root),
        }
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if restart:
            subprocess.Popen(
                [str(install_root / "BridgeMonitoringWorkbench.exe")],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=(subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0),
            )
        return InstalledUpdate(version, install_root, backup, log)
    except Exception as exc:
        if activated and backup.is_dir():
            shutil.rmtree(install_root, ignore_errors=True)
            backup.rename(install_root)
            activated = False
        elif swapped and backup.is_dir() and not install_root.exists():
            backup.rename(install_root)
            swapped = False
        shutil.rmtree(pending, ignore_errors=True)
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(json.dumps({
            "status": "failed",
            "version": version,
            "install_root": str(install_root),
            "source_root": str(source_root),
            "error": str(exc),
            "rolled_back": install_root.is_dir(),
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise


def launch_staged_installer(
    staged: StagedUpdate,
    install_root: Path,
    current_pid: int,
) -> subprocess.Popen[bytes]:
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    return subprocess.Popen(
        [
            str(staged.executable_path),
            "--install-staged-update",
            "--install-source", str(staged.package_root),
            "--install-root", str(install_root.resolve()),
            "--install-version", staged.version,
            "--wait-pid", str(int(current_pid)),
            "--restart-after-install",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=creationflags,
    )


def _ps_quote(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def write_install_script(
    staged: StagedUpdate,
    install_root: Path,
    current_pid: int,
    *,
    script_parent: Path | None = None,
) -> Path:
    install_root = install_root.resolve()
    if not (install_root / "BridgeMonitoringWorkbench.exe").is_file():
        raise UpdateSecurityError(f"安装目录无工作台 EXE：{install_root}")
    if staged.package_root.resolve() == install_root:
        raise UpdateSecurityError("更新暂存目录不能与当前安装目录相同")
    script = (script_parent or default_update_root()) / f"install_{staged.version}_{uuid.uuid4().hex[:8]}.ps1"
    script.parent.mkdir(parents=True, exist_ok=True)
    log_path = script.with_suffix(".log")
    content = f"""$ErrorActionPreference = 'Stop'
$source = {_ps_quote(staged.package_root)}
$target = {_ps_quote(install_root)}
$log = {_ps_quote(log_path)}
$backup = "$target.backup_{staged.version}_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
try {{
    Wait-Process -Id {int(current_pid)} -Timeout 120 -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath (Join-Path $source 'BridgeMonitoringWorkbench.exe'))) {{ throw 'staged exe missing' }}
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $backupCode = robocopy $target $backup /E /XD (Join-Path $target 'updates') /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -gt 7) {{ throw "backup failed: $LASTEXITCODE" }}
    foreach ($name in @('_internal','bin','reporting','reports')) {{
        $path = Join-Path $target $name
        if (Test-Path -LiteralPath $path) {{ Remove-Item -LiteralPath $path -Recurse -Force }}
    }}
    foreach ($name in @('BridgeMonitoringWorkbench.exe','README.md','VERSION','release_manifest.json','workbench_smoke.json','workbench_startup.png','workbench_alarm_editor.png','workbench_cleaning_editor.png','workbench_post_filter_editor.png','workbench_auto_threshold.png','workbench_offset_editor.png','workbench_group_plot_editor.png','workbench_plot_common_editor.png','workbench_spectrum_editor.png','workbench_report_task.png')) {{
        $path = Join-Path $target $name
        if (Test-Path -LiteralPath $path) {{ Remove-Item -LiteralPath $path -Force }}
    }}
    $copyCode = robocopy $source $target /E /XD (Join-Path $source 'config') /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -gt 7) {{ throw "install failed: $LASTEXITCODE" }}
    $sourceConfig = Join-Path $source 'config'
    $targetConfig = Join-Path $target 'config'
    New-Item -ItemType Directory -Path $targetConfig -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceConfig -File | ForEach-Object {{
        $targetFile = Join-Path $targetConfig $_.Name
        if (-not (Test-Path -LiteralPath $targetFile)) {{ Copy-Item -LiteralPath $_.FullName -Destination $targetFile }}
    }}
    Start-Process -FilePath (Join-Path $target 'BridgeMonitoringWorkbench.exe')
    "$(Get-Date -Format o) update installed; backup=$backup" | Set-Content -LiteralPath $log -Encoding UTF8
}} catch {{
    if (Test-Path -LiteralPath $backup) {{
        $restoreCode = robocopy $backup $target /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    }}
    "$(Get-Date -Format o) update failed: $($_.Exception.Message); backup=$backup" | Set-Content -LiteralPath $log -Encoding UTF8
    exit 1
}}
"""
    script.write_text(content, encoding="utf-8-sig")
    return script


def launch_install_script(script: Path) -> subprocess.Popen[bytes]:
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    return subprocess.Popen(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=creationflags,
    )
