from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
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
        yield member


def stage_verified_update(
    archive_path: Path,
    version: str,
    archive_sha256: str,
    staging_parent: Path,
) -> StagedUpdate:
    stage = staging_parent / f"{version}_{uuid.uuid4().hex[:8]}"
    stage.mkdir(parents=True, exist_ok=False)
    try:
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(stage, members=_safe_zip_members(archive))
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
        return StagedUpdate(version, archive_path, package_root, executable, manifest, archive_sha256)
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def default_update_root() -> Path:
    local = os.environ.get("LOCALAPPDATA")
    return Path(local or tempfile.gettempdir()) / "BridgeMonitoringWorkbench" / "updates"


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
    foreach ($name in @('BridgeMonitoringWorkbench.exe','README.md','VERSION','release_manifest.json','workbench_smoke.json','workbench_startup.png','workbench_alarm_editor.png')) {{
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
