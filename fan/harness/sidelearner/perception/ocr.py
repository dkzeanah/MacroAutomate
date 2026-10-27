"""OCR helper: pytesseract when available, empty string otherwise."""
from __future__ import annotations

import logging
from typing import Optional

log = logging.getLogger("sidelearner.perception.ocr")

_tesseract: Optional[object] = None
_tesseract_error: Optional[str] = None


def _load() -> Optional[object]:
    global _tesseract, _tesseract_error
    if _tesseract is None and _tesseract_error is None:
        try:
            import pytesseract  # type: ignore

            _tesseract = pytesseract
        except ImportError as exc:
            _tesseract_error = f"pytesseract not installed ({exc})"
        except Exception as exc:  # noqa: BLE001
            _tesseract_error = f"pytesseract unavailable ({exc})"
    return _tesseract


def ocr_available() -> bool:
    return _load() is not None


def ocr_text(image, lang: str = "eng") -> str:
    """OCR a PIL image. Returns '' when tesseract is unavailable."""
    pt = _load()
    if pt is None:
        log.debug("OCR skipped: %s", _tesseract_error)
        return ""
    try:
        return str(pt.image_to_string(image, lang=lang)).strip()
    except Exception as exc:  # noqa: BLE001
        log.warning("OCR failed: %s", exc)
        return ""
