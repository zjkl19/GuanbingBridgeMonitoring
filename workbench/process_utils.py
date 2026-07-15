from __future__ import annotations

import ctypes
import ctypes.wintypes
import json
import os
import signal
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Mapping


if os.name == "nt":
    _KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _KERNEL32.OpenProcess.argtypes = [
        ctypes.wintypes.DWORD,
        ctypes.wintypes.BOOL,
        ctypes.wintypes.DWORD,
    ]
    _KERNEL32.OpenProcess.restype = ctypes.wintypes.HANDLE
    _KERNEL32.CloseHandle.argtypes = [ctypes.wintypes.HANDLE]
    _KERNEL32.CloseHandle.restype = ctypes.wintypes.BOOL
    _KERNEL32.GetExitCodeProcess.argtypes = [
        ctypes.wintypes.HANDLE,
        ctypes.POINTER(ctypes.wintypes.DWORD),
    ]
    _KERNEL32.GetExitCodeProcess.restype = ctypes.wintypes.BOOL
    _KERNEL32.GetProcessTimes.argtypes = [
        ctypes.wintypes.HANDLE,
        ctypes.POINTER(ctypes.wintypes.FILETIME),
        ctypes.POINTER(ctypes.wintypes.FILETIME),
        ctypes.POINTER(ctypes.wintypes.FILETIME),
        ctypes.POINTER(ctypes.wintypes.FILETIME),
    ]
    _KERNEL32.GetProcessTimes.restype = ctypes.wintypes.BOOL
    _KERNEL32.QueryFullProcessImageNameW.argtypes = [
        ctypes.wintypes.HANDLE,
        ctypes.wintypes.DWORD,
        ctypes.wintypes.LPWSTR,
        ctypes.POINTER(ctypes.wintypes.DWORD),
    ]
    _KERNEL32.QueryFullProcessImageNameW.restype = ctypes.wintypes.BOOL
    _KERNEL32.TerminateProcess.argtypes = [
        ctypes.wintypes.HANDLE,
        ctypes.wintypes.UINT,
    ]
    _KERNEL32.TerminateProcess.restype = ctypes.wintypes.BOOL
    _KERNEL32.WaitForSingleObject.argtypes = [
        ctypes.wintypes.HANDLE,
        ctypes.wintypes.DWORD,
    ]
    _KERNEL32.WaitForSingleObject.restype = ctypes.wintypes.DWORD
else:  # pragma: no cover - platform declaration
    _KERNEL32 = None


def atomic_write_json(path: Path | str, payload: Mapping[str, Any]) -> Path:
    """Publish one JSON object without exposing a partially written target."""

    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(
        f".{target.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp"
    )
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as stream:
            json.dump(dict(payload), stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        for attempt in range(5):
            try:
                temporary.replace(target)
                break
            except PermissionError:
                # Windows antivirus/indexers can briefly open a JSON file
                # without delete sharing.  Keep the publication atomic and
                # retry for a short, bounded interval rather than falling back
                # to an in-place overwrite.
                if attempt == 4:
                    raise
                time.sleep(0.02 * (attempt + 1))
    finally:
        temporary.unlink(missing_ok=True)
    return target


@contextmanager
def exclusive_file_lock(path: Path | str) -> Iterator[Path]:
    """Hold a non-blocking, process-wide launch transaction lock."""

    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    stream = target.open("a+b")
    try:
        if stream.seek(0, os.SEEK_END) == 0:
            stream.write(b"\0")
            stream.flush()
        stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (OSError, PermissionError) as exc:
            raise RuntimeError(
                f"任务正在由另一个工作台实例启动，请稍后重试：{target}"
            ) from exc
        try:
            yield target
        finally:
            stream.seek(0)
            if os.name == "nt":
                import msvcrt

                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
    finally:
        stream.close()


def assert_no_live_process_lease(path: Path | str, task_label: str) -> None:
    """Fail closed when a shared runtime lease still owns a live process.

    Callers must hold the corresponding runtime-directory launch lock.  A dead
    or PID-reused lease is removed so a copied/renamed job context can recover
    without allowing two workers to write the same output tree.
    """

    target = Path(path)
    payload = read_process_lease(target, task_label=task_label)
    if payload is None:
        return
    pid = int(payload["pid"])
    created = payload.get("process_creation_time_100ns")
    executable = str(payload.get("process_executable") or "")
    if created and executable:
        identity_state = process_identity_state(pid, int(created), executable)
        if identity_state == "unverifiable":
            raise RuntimeError(
                f"{task_label}后台进程仍存在，但暂时无法核验其身份（PID {pid}）；"
                "为避免重复运行，未启动新任务。"
            )
        if identity_state in {"dead", "reused"}:
            # The PID is live but belongs to a different process.  The old
            # lease is stale and can be reclaimed under the shared lock.
            target.unlink(missing_ok=True)
            return
        alive = identity_state == "matching"
    else:
        alive = pid_running(pid)
    if alive:
        raise RuntimeError(
            f"{task_label}已有后台进程正在运行（PID {pid}），未启动重复任务。"
        )
    target.unlink(missing_ok=True)


def read_process_lease(
    path: Path | str, *, task_label: str = "任务"
) -> dict[str, Any] | None:
    """Read and validate a process lease, failing closed on corruption."""

    target = Path(path)
    if not target.is_file():
        return None
    try:
        payload = json.loads(target.read_text(encoding="utf-8-sig"))
        if not isinstance(payload, dict):
            raise ValueError("lease is not a JSON object")
        launch_id = str(payload.get("launch_id") or "")
        pid = int(payload.get("pid") or 0)
        if not launch_id or pid <= 0:
            raise ValueError("lease is missing launch_id or pid")
        payload["launch_id"] = launch_id
        payload["pid"] = pid
        return payload
    except (OSError, ValueError, TypeError) as exc:
        raise RuntimeError(
            f"{task_label}活动租约损坏，无法安全判断是否已有任务：{target}"
        ) from exc


def publish_process_lease(
    path: Path | str,
    *,
    task_type: str,
    launch_id: str,
    pid: int,
    process_creation_time_100ns: int,
    process_executable: str,
    context_path: Path | str,
    job_id: str = "",
) -> Path:
    return atomic_write_json(
        path,
        {
            "schema_version": 1,
            "state": "active",
            "task_type": task_type,
            "launch_id": launch_id,
            "pid": int(pid),
            "process_creation_time_100ns": int(process_creation_time_100ns),
            "process_executable": str(process_executable),
            "context_path": str(Path(context_path).expanduser().resolve()),
            "job_id": str(job_id),
        },
    )


def clear_process_lease(path: Path | str, launch_id: str) -> bool:
    """Remove only the lease owned by *launch_id*.

    Callers must hold the corresponding runtime lock.  A stale window must
    never clear a newer worker's lease.
    """

    target = Path(path)
    payload = read_process_lease(target)
    if payload is None or str(payload.get("launch_id") or "") != str(launch_id):
        return False
    target.unlink(missing_ok=True)
    return True


def pid_running(pid: int | None) -> bool:
    """Return whether *pid* still represents a live process.

    The workbench launches detached MATLAB/compiled workers, so ``Popen``
    objects are intentionally not retained.  Keep the platform-specific probe
    in one place so analysis and report tasks make the same lifecycle decision.
    """

    if not pid or pid <= 0:
        return False
    if os.name != "nt":
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    process_query_limited_information = 0x1000
    still_active = 259
    assert _KERNEL32 is not None
    handle = _KERNEL32.OpenProcess(
        process_query_limited_information, False, int(pid)
    )
    if not handle:
        # ERROR_INVALID_PARAMETER is the normal "PID does not exist" result.
        # Access denied and other query failures are not proof of death; treat
        # them as possibly live so leases fail closed instead of being
        # reclaimed while an inaccessible worker still owns the output tree.
        return ctypes.get_last_error() != 87
    try:
        exit_code = ctypes.c_ulong()
        if not _KERNEL32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
            return True
        return exit_code.value == still_active
    finally:
        _KERNEL32.CloseHandle(handle)


def process_identity(pid: int | None) -> dict[str, Any] | None:
    """Return a stable identity for a live process, not merely its PID.

    Windows can recycle process identifiers quickly.  Detached task records
    therefore bind the PID to both its creation FILETIME and executable path
    before any later force-stop operation is allowed.
    """

    if not pid or pid <= 0:
        return None
    if os.name == "nt":
        process_query_limited_information = 0x1000
        assert _KERNEL32 is not None
        handle = _KERNEL32.OpenProcess(
            process_query_limited_information, False, int(pid)
        )
        if not handle:
            return None
        try:
            return _windows_identity_from_handle(handle, int(pid))
        finally:
            _KERNEL32.CloseHandle(handle)

    proc_root = Path("/proc") / str(int(pid))
    try:
        raw_stat = (proc_root / "stat").read_text(encoding="utf-8")
        # ``comm`` is parenthesized and may itself contain spaces.  Field 22
        # (starttime) is index 19 after the closing parenthesis, not reliably
        # index 21 after a naive whitespace split.
        closing = raw_stat.rfind(")")
        if closing < 0:
            return None
        fields_after_comm = raw_stat[closing + 1 :].split()
        executable = str((proc_root / "exe").resolve(strict=True))
        return {
            "pid": int(pid),
            "creation_time_100ns": int(fields_after_comm[19]),
            "executable": executable,
        }
    except (OSError, IndexError, ValueError):
        return None


def capture_process_identity(
    pid: int | None,
    *,
    attempts: int = 10,
    delay_seconds: float = 0.02,
) -> dict[str, Any] | None:
    """Capture a new child identity with a short bounded startup retry."""

    for attempt in range(max(1, int(attempts))):
        try:
            identity = process_identity(pid)
        except Exception:  # pragma: no cover - defensive OS API boundary
            identity = None
        if identity is not None:
            return identity
        if attempt + 1 < max(1, int(attempts)):
            time.sleep(max(0.0, float(delay_seconds)))
    return None


def capture_spawned_process_identity(
    process: Any,
    *,
    attempts: int = 10,
    delay_seconds: float = 0.02,
) -> dict[str, Any] | None:
    """Capture a child identity through the process handle returned by spawn.

    On Windows, reopening by PID after ``Popen`` creates a PID-reuse race when
    a very short-lived child exits.  The original ``Popen`` handle therefore
    remains authoritative throughout identity registration.
    """

    pid = int(getattr(process, "pid", 0) or 0)
    if pid <= 0:
        return None
    if os.name != "nt":
        return capture_process_identity(
            pid, attempts=attempts, delay_seconds=delay_seconds
        )

    raw_handle = getattr(process, "_handle", None)
    if raw_handle is None:
        return None
    try:
        handle = ctypes.wintypes.HANDLE(int(raw_handle))
    except (TypeError, ValueError, OverflowError):
        return None
    assert _KERNEL32 is not None
    still_active = 259
    limit = max(1, int(attempts))
    for attempt in range(limit):
        before = ctypes.wintypes.DWORD()
        if not _KERNEL32.GetExitCodeProcess(handle, ctypes.byref(before)):
            return None
        if int(before.value) != still_active:
            return None
        identity = _windows_identity_from_handle(handle, pid)
        after = ctypes.wintypes.DWORD()
        if not _KERNEL32.GetExitCodeProcess(handle, ctypes.byref(after)):
            return None
        if identity is not None and int(after.value) == still_active:
            return identity
        if attempt + 1 < limit:
            time.sleep(max(0.0, float(delay_seconds)))
    return None


def process_matches(
    pid: int | None,
    creation_time_100ns: int | None,
    executable: str,
) -> bool:
    """Return whether a live PID is the exact process captured at launch."""

    if not pid or not creation_time_100ns or not str(executable).strip():
        return False
    return (
        process_identity_state(pid, creation_time_100ns, executable)
        == "matching"
    )


def process_identity_state(
    pid: int | None,
    creation_time_100ns: int | None,
    executable: str,
) -> str:
    """Return matching, reused, dead or unverifiable for a stored identity."""

    if not pid or not creation_time_100ns or not str(executable).strip():
        return "dead"
    actual = process_identity(pid)
    if actual is not None:
        return (
            "matching"
            if _identity_matches(actual, int(creation_time_100ns), executable)
            else "reused"
        )
    return "unverifiable" if pid_running(pid) else "dead"


def terminate_exact_process(
    pid: int | None,
    creation_time_100ns: int | None,
    executable: str,
    *,
    timeout_seconds: float = 2.0,
) -> bool:
    """Terminate only the exact process captured at launch.

    A separate ``process_matches`` call followed by ``taskkill /PID`` still
    has a small PID-reuse window.  Windows therefore validates creation time
    and executable path and calls ``TerminateProcess`` while retaining the
    same process handle.  Linux uses a pidfd when the runtime exposes it.
    """

    if not pid or not creation_time_100ns or not str(executable).strip():
        return False
    if os.name == "nt":
        process_terminate = 0x0001
        process_query_limited_information = 0x1000
        synchronize = 0x00100000
        assert _KERNEL32 is not None
        handle = _KERNEL32.OpenProcess(
            process_terminate | process_query_limited_information | synchronize,
            False,
            int(pid),
        )
        if not handle:
            return False
        try:
            actual = _windows_identity_from_handle(handle, int(pid))
            if actual is None or not _identity_matches(
                actual, creation_time_100ns, executable
            ):
                return False
            if not _KERNEL32.TerminateProcess(handle, 1):
                error_code = ctypes.get_last_error()
                raise OSError(error_code, ctypes.FormatError(error_code))
            wait_object_0 = 0
            wait_timeout = 258
            wait_failed = 0xFFFFFFFF
            milliseconds = max(0, round(float(timeout_seconds) * 1000))
            wait_result = int(_KERNEL32.WaitForSingleObject(handle, milliseconds))
            if wait_result == wait_object_0:
                return True
            if wait_result == wait_timeout:
                raise TimeoutError(
                    "已向目标进程发送终止请求，但等待进程退出超时。"
                )
            if wait_result == wait_failed:
                error_code = ctypes.get_last_error()
                raise OSError(error_code, ctypes.FormatError(error_code))
            raise OSError(f"WaitForSingleObject returned unexpected code {wait_result}")
        finally:
            _KERNEL32.CloseHandle(handle)

    pidfd_open = getattr(os, "pidfd_open", None)
    pidfd_send_signal = getattr(signal, "pidfd_send_signal", None)
    if callable(pidfd_open) and callable(pidfd_send_signal):
        try:
            descriptor = pidfd_open(int(pid), 0)
        except OSError:
            return False
        try:
            actual = process_identity(pid)
            if actual is None or not _identity_matches(
                actual, creation_time_100ns, executable
            ):
                return False
            pidfd_send_signal(descriptor, signal.SIGTERM, None, 0)
            return True
        finally:
            os.close(descriptor)

    # Compatibility fallback for non-Linux POSIX test/development hosts.  The
    # production application runs on Windows and uses the handle-safe branch.
    if not process_matches(pid, creation_time_100ns, executable):
        return False
    os.kill(int(pid), signal.SIGTERM)
    return True


def _windows_identity_from_handle(handle: int, pid: int) -> dict[str, Any] | None:
    creation = ctypes.wintypes.FILETIME()
    exit_time = ctypes.wintypes.FILETIME()
    kernel_time = ctypes.wintypes.FILETIME()
    user_time = ctypes.wintypes.FILETIME()
    assert _KERNEL32 is not None
    if not _KERNEL32.GetProcessTimes(
        handle,
        ctypes.byref(creation),
        ctypes.byref(exit_time),
        ctypes.byref(kernel_time),
        ctypes.byref(user_time),
    ):
        return None
    capacity = ctypes.wintypes.DWORD(32768)
    executable = ctypes.create_unicode_buffer(capacity.value)
    if not _KERNEL32.QueryFullProcessImageNameW(
        handle, 0, executable, ctypes.byref(capacity)
    ):
        return None
    created = (int(creation.dwHighDateTime) << 32) | int(creation.dwLowDateTime)
    return {
        "pid": int(pid),
        "creation_time_100ns": created,
        "executable": executable.value,
    }


def _identity_matches(
    actual: Mapping[str, Any], creation_time_100ns: int, executable: str
) -> bool:
    actual_path = os.path.normcase(os.path.realpath(str(actual["executable"])))
    expected_path = os.path.normcase(os.path.realpath(str(executable)))
    return (
        int(actual["creation_time_100ns"]) == int(creation_time_100ns)
        and actual_path == expected_path
    )
