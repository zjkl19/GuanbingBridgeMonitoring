from __future__ import annotations

import os
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path


WORD_PDF_FORMAT = 17


@dataclass(frozen=True)
class WordPdfExportResult:
    path: Path | None
    status: str
    message: str = ""
    authoritative: bool = False
    source: str = "microsoft_word_dispatch_ex"

    def to_dict(self) -> dict[str, object]:
        payload = asdict(self)
        payload["path"] = str(self.path or "")
        return payload


def _update_fields(document) -> None:
    """Refresh body/header/footer fields without depending on an open UI Word."""
    for story in document.StoryRanges:
        current = story
        for _ in range(64):
            if current is None:
                break
            try:
                current.Fields.Update()
            except Exception:  # noqa: BLE001 - one unsupported story must not skip the rest
                pass
            try:
                current = current.NextStoryRange
            except Exception:  # noqa: BLE001
                break
    for collection_name in ("TablesOfContents", "TablesOfFigures", "TablesOfAuthorities"):
        try:
            collection = getattr(document, collection_name)
            for item in collection:
                item.Update()
        except Exception:  # noqa: BLE001 - a report may not contain this field collection
            pass
    document.Fields.Update()


def export_authoritative_word_pdf(
    docx_path: Path,
    pdf_path: Path | None = None,
) -> WordPdfExportResult:
    """Export a report through an isolated Microsoft Word ``DispatchEx`` instance.

    The report worker is already a background process, and ``DispatchEx`` creates
    a separate Word automation instance instead of borrowing the operator's open
    Word window.  Export goes to a temporary sibling and is atomically promoted
    only after Word produced a non-empty PDF, so a failed run cannot reuse a
    stale adjacent PDF as an authoritative deliverable.
    """
    source = Path(docx_path).expanduser().resolve()
    if not source.is_file():
        return WordPdfExportResult(None, "failed", f"DOCX does not exist: {source}")
    if os.environ.get("BMS_NO_WORD") == "1":
        return WordPdfExportResult(None, "skipped", "BMS_NO_WORD=1")
    if os.name != "nt":
        return WordPdfExportResult(None, "unavailable", "Microsoft Word export requires Windows")

    try:
        import pythoncom
        import win32com.client  # type: ignore
    except ImportError as exc:
        return WordPdfExportResult(None, "unavailable", f"Word COM runtime unavailable: {exc}")

    target = (pdf_path or source.with_suffix(".pdf")).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(
        f".{target.stem}.{os.getpid()}.{uuid.uuid4().hex}.word-export.pdf"
    )
    word = None
    document = None
    pythoncom.CoInitialize()
    try:
        word = win32com.client.DispatchEx("Word.Application")
        word.Visible = False
        word.DisplayAlerts = 0
        document = word.Documents.Open(
            str(source),
            ReadOnly=False,
            AddToRecentFiles=False,
            Visible=False,
        )
        _update_fields(document)
        document.Save()
        document.ExportAsFixedFormat(str(temporary), WORD_PDF_FORMAT)
        if not temporary.is_file() or temporary.stat().st_size <= 0:
            raise RuntimeError("Microsoft Word did not produce a non-empty PDF")
        temporary.replace(target)
        return WordPdfExportResult(
            target,
            "passed",
            authoritative=True,
        )
    except Exception as exc:  # noqa: BLE001 - failure is downgraded to preview-only mode
        return WordPdfExportResult(
            None,
            "failed",
            f"{type(exc).__name__}: {exc}",
        )
    finally:
        if document is not None:
            try:
                document.Close(SaveChanges=False)
            except Exception:  # noqa: BLE001
                pass
        if word is not None:
            try:
                word.Quit()
            except Exception:  # noqa: BLE001
                pass
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        pythoncom.CoUninitialize()
