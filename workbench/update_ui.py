from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from PySide6.QtCore import QSettings, QThread, QTimer, QUrl, Signal
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QApplication, QCheckBox, QMainWindow, QMessageBox, QPushButton

from .updater import (
    GitHubReleaseClient,
    StagedUpdate,
    UpdateInfo,
    UpdatePolicy,
    default_update_root,
    cleanup_update_backups,
    discover_update_backups,
    launch_staged_installer,
    stage_verified_update,
)
from .operator_text import operator_friendly_text
from .version import app_version


class UpdateCheckThread(QThread):
    completed = Signal(object)
    failed = Signal(str)

    def __init__(self, policy: UpdatePolicy, current_version: str) -> None:
        super().__init__()
        self.policy = policy
        self.current_version = current_version

    def run(self) -> None:
        try:
            self.completed.emit(GitHubReleaseClient(self.policy).latest_release(self.current_version))
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))


class UpdateDownloadThread(QThread):
    completed = Signal(object)
    failed = Signal(str)
    progress = Signal(int)

    def __init__(self, policy: UpdatePolicy, info: UpdateInfo) -> None:
        super().__init__()
        self.policy = policy
        self.info = info

    def run(self) -> None:
        try:
            root = default_update_root()
            download_dir = root / "downloads" / self.info.latest_version

            def report(received: int, total: int) -> None:
                if total > 0:
                    self.progress.emit(max(0, min(100, round(received * 100 / total))))

            archive, digest = GitHubReleaseClient(self.policy).download_verified_package(
                self.info, download_dir, report
            )
            staged = stage_verified_update(
                archive,
                self.info.latest_version,
                digest,
                root / "staged",
            )
            self.completed.emit(staged)
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))


class UpdateController:
    def __init__(
        self,
        window: QMainWindow,
        button: QPushButton,
        project_root: Path,
        backup_button: QPushButton | None = None,
        auto_check_box: QCheckBox | None = None,
        settings: QSettings | None = None,
    ) -> None:
        self.window = window
        self.button = button
        self.project_root = project_root.resolve()
        self.current_version = app_version(self.project_root)
        self.policy = UpdatePolicy.load(self.project_root)
        self.settings = settings or QSettings("Guanbing", "BridgeMonitoringWorkbench")
        self.worker: QThread | None = None
        self.manual = False
        self.button.clicked.connect(lambda: self.check(manual=True))
        self.auto_check_box = auto_check_box
        if self.auto_check_box is not None:
            stored = self.settings.value("updates/auto_check_enabled", None)
            enabled = self.policy.auto_check if stored is None else str(stored).lower() in {
                "1", "true", "yes", "on"
            }
            self.auto_check_box.setChecked(enabled)
            self.auto_check_box.toggled.connect(self.set_auto_check_enabled)
        self.backup_button = backup_button
        if self.backup_button is not None:
            self.backup_button.clicked.connect(self.manage_backups)

    def auto_check_enabled(self) -> bool:
        if self.auto_check_box is not None:
            return self.auto_check_box.isChecked()
        stored = self.settings.value("updates/auto_check_enabled", None)
        return self.policy.auto_check if stored is None else str(stored).lower() in {
            "1", "true", "yes", "on"
        }

    def set_auto_check_enabled(self, enabled: bool) -> None:
        self.settings.setValue("updates/auto_check_enabled", bool(enabled))

    def manage_backups(self) -> None:
        backups = discover_update_backups(self.project_root)
        if not backups:
            QMessageBox.information(
                self.window,
                "更新备份",
                f"当前安装目录旁没有识别到工作台更新备份。\n\n{self.project_root.parent}",
            )
            return
        safe = [item for item in backups if item.safe_to_remove]
        lines = []
        for index, item in enumerate(backups, 1):
            state = "可清理" if item.safe_to_remove else f"保留：{item.issue}"
            lines.append(
                f"{index}. 原版本 {item.version} → 更新目标 {item.replaced_by_version}　"
                f"{item.created_at}　{state}\n   {item.path}"
            )
        box = QMessageBox(self.window)
        box.setWindowTitle("更新备份")
        box.setIcon(QMessageBox.Information)
        box.setText(f"识别到 {len(backups)} 个更新备份，其中 {len(safe)} 个身份闭合。")
        box.setInformativeText("清理操作始终保留最新 2 个身份闭合的备份；异常备份不会自动删除。")
        box.setDetailedText("\n".join(lines))
        cleanup_button = None
        if len(safe) > 2:
            cleanup_button = box.addButton("清理旧备份（保留最新2个）", QMessageBox.DestructiveRole)
        open_button = box.addButton("打开备份目录", QMessageBox.ActionRole)
        box.addButton("关闭", QMessageBox.RejectRole)
        box.exec()
        clicked = box.clickedButton()
        if clicked is open_button:
            if os.name == "nt":
                os.startfile(self.project_root.parent)  # type: ignore[attr-defined]
            else:
                QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.project_root.parent)))
        elif cleanup_button is not None and clicked is cleanup_button:
            answer = QMessageBox.question(
                self.window,
                "确认清理旧更新备份",
                f"将删除 {len(safe) - 2} 个较旧且身份闭合的备份，并保留最新 2 个。\n"
                "清单异常或无法识别的目录不会删除。是否继续？",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No,
            )
            if answer != QMessageBox.Yes:
                return
            try:
                removed = cleanup_update_backups(self.project_root, keep_latest=2)
            except Exception as exc:  # noqa: BLE001
                QMessageBox.critical(self.window, "更新备份清理失败", str(exc))
                return
            QMessageBox.information(
                self.window,
                "更新备份清理完成",
                f"已删除 {len(removed)} 个旧备份；最新 2 个身份闭合备份仍保留。",
            )

    def schedule_auto_check(self) -> None:
        if (
            not getattr(sys, "frozen", False)
            or not self.auto_check_enabled()
            or "-" in self.current_version
            or "+" in self.current_version
        ):
            return
        last = float(self.settings.value("updates/last_check_epoch", 0.0) or 0.0)
        if time.time() - last < self.policy.check_interval_hours * 3600:
            return
        QTimer.singleShot(self.policy.startup_delay_seconds * 1000, lambda: self.check(manual=False))

    def check(self, *, manual: bool) -> None:
        if self.worker is not None and self.worker.isRunning():
            return
        self.manual = manual
        self.button.setEnabled(False)
        self.button.setText("正在检查更新…")
        worker = UpdateCheckThread(self.policy, self.current_version)
        worker.completed.connect(self._check_completed)
        worker.failed.connect(self._operation_failed)
        worker.finished.connect(lambda: self._worker_finished(worker))
        self.worker = worker
        worker.start()

    def _worker_finished(self, finished_worker: QThread) -> None:
        finished_worker.deleteLater()
        # A successful check can start the download worker before the check
        # thread emits finished. Never clear or re-enable over that new worker.
        if self.worker is finished_worker:
            self.worker = None
            self.button.setEnabled(True)
            self.button.setText("立即检查更新")

    def _check_completed(self, info: UpdateInfo) -> None:
        self.settings.setValue("updates/last_check_epoch", time.time())
        if not info.update_available:
            if self.manual:
                QMessageBox.information(
                    self.window,
                    "已经是最新版本",
                    f"当前版本：{self.current_version}\nGitHub 最新正式版：{info.latest_version}",
                )
            return
        box = QMessageBox(self.window)
        box.setWindowTitle("发现工作台更新")
        box.setIcon(QMessageBox.Information)
        box.setText(f"发现新版本 {info.latest_version}（当前 {self.current_version}）")
        notes = info.release_notes.strip() or "该 Release 未填写更新说明。"
        if len(notes) > 1500:
            notes = notes[:1500] + "\n…"
        box.setDetailedText(notes)
        download_button = None
        if info.installable and getattr(sys, "frozen", False):
            download_button = box.addButton("下载并安装", QMessageBox.AcceptRole)
        github_button = box.addButton("打开 GitHub Release", QMessageBox.ActionRole)
        box.addButton("稍后", QMessageBox.RejectRole)
        box.exec()
        clicked = box.clickedButton()
        if clicked is github_button and info.html_url:
            QDesktopServices.openUrl(QUrl(info.html_url))
        elif download_button is not None and clicked is download_button:
            self._download(info)

    def _download(self, info: UpdateInfo) -> None:
        self.button.setEnabled(False)
        self.button.setText("正在下载更新…")
        worker = UpdateDownloadThread(self.policy, info)
        worker.progress.connect(lambda value: self.button.setText(f"正在下载更新… {value}%"))
        worker.completed.connect(self._download_completed)
        worker.failed.connect(self._operation_failed)
        worker.finished.connect(lambda: self._worker_finished(worker))
        self.worker = worker
        worker.start()

    def _download_completed(self, staged: StagedUpdate) -> None:
        answer = QMessageBox.question(
            self.window,
            "更新已验证",
            f"版本 {staged.version} 已下载并通过双重 SHA256 校验。\n\n"
            "安装时工作台将退出，自动备份当前安装目录，保留现有 config，"
            "更新完成后重新启动。是否现在安装？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer != QMessageBox.Yes:
            return
        try:
            launch_staged_installer(staged, self.project_root, os.getpid())
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(
                self.window,
                "无法启动更新安装",
                operator_friendly_text(exc),
            )
            return
        QApplication.quit()

    def _operation_failed(self, message: str) -> None:
        display_message = operator_friendly_text(message)
        if "尚未发布正式 Release" in message:
            self.settings.setValue("updates/last_check_epoch", time.time())
        if self.manual:
            if "尚未发布正式 Release" in message:
                QMessageBox.information(self.window, "暂无正式更新", display_message)
            else:
                QMessageBox.warning(self.window, "更新检查失败", display_message)
