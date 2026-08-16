from __future__ import annotations

import ctypes
import json
import os
import platform
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable


APP_NAME = "OllamaJobAutomationStudio"
RECOMMENDED_ENV = {
    "OLLAMA_MAX_LOADED_MODELS": "1",
    "OLLAMA_NUM_PARALLEL": "1",
    "OLLAMA_CONTEXT_LENGTH": "8192",
}

MODEL_CATALOG = [
    {
        "name": "qwen3.5:4b",
        "role": "Primary agent",
        "description": "General controller, tool-oriented reasoning, and grounded writing.",
    },
    {
        "name": "qwen2.5-coder:7b",
        "role": "Coding",
        "description": "Source-code generation, review, refactoring, and debugging.",
    },
    {
        "name": "granite3.2-vision:2b",
        "role": "Document vision",
        "description": "OCR-like document, table, receipt, and screenshot understanding.",
    },
    {
        "name": "qwen3-vl:4b",
        "role": "Advanced vision",
        "description": "Complex webpage and image reasoning.",
    },
    {
        "name": "deepseek-r1:7b",
        "role": "Reasoning fallback",
        "description": "Slower difficult planning and reasoning tasks.",
    },
    {
        "name": "embeddinggemma",
        "role": "Memory / RAG",
        "description": "Embeddings for semantic profile, resume, and document retrieval.",
    },
]


def app_data_dir() -> Path:
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    path = base / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


@dataclass(frozen=True)
class AppPaths:
    root: Path
    data: Path
    logs: Path
    browser_profile: Path
    downloads: Path
    rag_db: Path
    profile_json: Path
    rules_json: Path
    settings_json: Path

    @classmethod
    def create(cls) -> "AppPaths":
        root = app_data_dir()
        data = root / "data"
        logs = root / "logs"
        browser_profile = root / "browser_profile"
        downloads = root / "downloads"
        for folder in (data, logs, browser_profile, downloads):
            folder.mkdir(parents=True, exist_ok=True)
        return cls(
            root=root,
            data=data,
            logs=logs,
            browser_profile=browser_profile,
            downloads=downloads,
            rag_db=data / "rag.sqlite3",
            profile_json=data / "profile.json",
            rules_json=data / "answer_rules.json",
            settings_json=data / "settings.json",
        )


class AtomicJSON:
    @staticmethod
    def load(path: Path, default: Any) -> Any:
        try:
            with path.open("r", encoding="utf-8") as handle:
                return json.load(handle)
        except FileNotFoundError:
            return default
        except (OSError, json.JSONDecodeError):
            return default

    @staticmethod
    def save(path: Path, data: Any) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            delete=False,
            dir=str(path.parent),
            suffix=".tmp",
        ) as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            temp_name = handle.name
        os.replace(temp_name, path)


def default_profile() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "identity": {
            "first_name": "",
            "middle_name": "",
            "last_name": "",
            "preferred_name": "",
            "email": "",
            "phone": "",
            "address_line_1": "",
            "address_line_2": "",
            "city": "",
            "state": "",
            "postal_code": "",
            "country": "United States",
        },
        "links": {
            "linkedin": "",
            "github": "",
            "portfolio": "",
            "website": "",
        },
        "current_work": {
            "employer": "",
            "title": "",
            "start_date": "",
        },
        "education": {
            "school": "",
            "degree": "",
            "field_of_study": "",
            "graduation_date": "",
        },
        "documents": {
            "resume_path": "",
            "cover_letter_path": "",
        },
        "skills": [],
        "work_history": [],
        "education_history": [],
        "verified_facts": [],
        "preferences": {
            "remote": "",
            "locations": [],
            "minimum_salary": "",
        },
        "notes": (
            "Store only facts you can verify. The application assistant does not "
            "invent credentials, dates, experience, authorization, or legal answers."
        ),
    }


def default_rules() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "manual_only_keywords": [
            "gender",
            "sex",
            "race",
            "ethnicity",
            "disability",
            "veteran",
            "medical",
            "pregnan",
            "religion",
            "date of birth",
            "birth date",
            "age",
            "social security",
            "ssn",
            "criminal",
            "conviction",
            "background check",
            "credit",
            "work authorization",
            "authorized to work",
            "visa",
            "sponsor",
            "citizen",
            "salary",
            "compensation",
            "pay expectation",
            "desired pay",
            "attest",
            "certify",
            "signature",
            "terms",
            "consent",
        ],
        "safe_field_aliases": {
            "first_name": ["first name", "given name", "firstname", "fname"],
            "middle_name": ["middle name", "middle initial"],
            "last_name": ["last name", "surname", "family name", "lastname", "lname"],
            "preferred_name": ["preferred name", "nickname"],
            "email": ["email", "email address"],
            "phone": ["phone", "phone number", "mobile", "telephone"],
            "address_line_1": ["address", "street address", "address line 1"],
            "address_line_2": ["address line 2", "apartment", "suite", "unit"],
            "city": ["city", "town"],
            "state": ["state", "province", "region"],
            "postal_code": ["zip", "zip code", "postal", "postal code"],
            "country": ["country"],
            "linkedin": ["linkedin", "linkedin profile"],
            "github": ["github", "github profile"],
            "portfolio": ["portfolio", "portfolio url"],
            "website": ["website", "personal website", "site url"],
            "current_employer": ["current employer", "current company", "employer"],
            "current_title": ["current title", "job title", "current position"],
            "school": ["school", "college", "university"],
            "degree": ["degree"],
            "field_of_study": ["field of study", "major"],
            "graduation_date": ["graduation date", "graduated"],
            "resume_path": ["resume", "résumé", "cv", "curriculum vitae"],
        },
    }


def flatten_profile(profile: dict[str, Any]) -> dict[str, Any]:
    identity = profile.get("identity", {})
    links = profile.get("links", {})
    current = profile.get("current_work", {})
    education = profile.get("education", {})
    documents = profile.get("documents", {})
    result = {
        "first_name": identity.get("first_name", ""),
        "middle_name": identity.get("middle_name", ""),
        "last_name": identity.get("last_name", ""),
        "preferred_name": identity.get("preferred_name", ""),
        "email": identity.get("email", ""),
        "phone": identity.get("phone", ""),
        "address_line_1": identity.get("address_line_1", ""),
        "address_line_2": identity.get("address_line_2", ""),
        "city": identity.get("city", ""),
        "state": identity.get("state", ""),
        "postal_code": identity.get("postal_code", ""),
        "country": identity.get("country", ""),
        "linkedin": links.get("linkedin", ""),
        "github": links.get("github", ""),
        "portfolio": links.get("portfolio", ""),
        "website": links.get("website", ""),
        "current_employer": current.get("employer", ""),
        "current_title": current.get("title", ""),
        "school": education.get("school", ""),
        "degree": education.get("degree", ""),
        "field_of_study": education.get("field_of_study", ""),
        "graduation_date": education.get("graduation_date", ""),
        "resume_path": documents.get("resume_path", ""),
        "cover_letter_path": documents.get("cover_letter_path", ""),
    }
    return result


class EnvironmentManager:
    @staticmethod
    def apply_recommended() -> dict[str, str]:
        for key, value in RECOMMENDED_ENV.items():
            os.environ[key] = value

        if os.name == "nt":
            import winreg

            with winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                "Environment",
                0,
                winreg.KEY_SET_VALUE,
            ) as key:
                for name, value in RECOMMENDED_ENV.items():
                    winreg.SetValueEx(key, name, 0, winreg.REG_SZ, value)

            HWND_BROADCAST = 0xFFFF
            WM_SETTINGCHANGE = 0x001A
            SMTO_ABORTIFHUNG = 0x0002
            result = ctypes.c_ulong()
            ctypes.windll.user32.SendMessageTimeoutW(
                HWND_BROADCAST,
                WM_SETTINGCHANGE,
                0,
                "Environment",
                SMTO_ABORTIFHUNG,
                5000,
                ctypes.byref(result),
            )
        else:
            shell_file = Path.home() / ".profile"
            marker_start = "# BEGIN OLLAMA JOB STUDIO"
            marker_end = "# END OLLAMA JOB STUDIO"
            existing = shell_file.read_text(encoding="utf-8") if shell_file.exists() else ""
            block = marker_start + "\n"
            block += "\n".join(
                f'export {key}="{value}"' for key, value in RECOMMENDED_ENV.items()
            )
            block += "\n" + marker_end
            if marker_start in existing and marker_end in existing:
                before = existing.split(marker_start, 1)[0].rstrip()
                after = existing.split(marker_end, 1)[1].lstrip()
                existing = f"{before}\n\n{block}\n\n{after}".strip() + "\n"
            else:
                existing = existing.rstrip() + "\n\n" + block + "\n"
            shell_file.write_text(existing, encoding="utf-8")
        return dict(RECOMMENDED_ENV)


def which_ollama() -> str | None:
    return shutil.which("ollama") or shutil.which("ollama.exe")


def system_report() -> str:
    lines = [
        f"Python: {sys.version.splitlines()[0]}",
        f"Executable: {sys.executable}",
        f"OS: {platform.platform()}",
        f"Machine: {platform.machine()}",
        f"Processor: {platform.processor() or 'Unknown'}",
        f"Ollama executable: {which_ollama() or 'Not found on PATH'}",
        "",
        "Recommended Ollama environment:",
    ]
    for key, value in RECOMMENDED_ENV.items():
        lines.append(f"  {key}={os.environ.get(key, '<not set>')} (recommended {value})")

    if os.name == "nt":
        try:
            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]

            status = MEMORYSTATUSEX()
            status.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
            gib = 1024 ** 3
            lines.append(f"\nRAM: {status.ullTotalPhys / gib:.1f} GiB total, "
                         f"{status.ullAvailPhys / gib:.1f} GiB available")
        except Exception:
            pass

    nvidia_smi = shutil.which("nvidia-smi")
    if nvidia_smi:
        try:
            result = subprocess.run(
                [
                    nvidia_smi,
                    "--query-gpu=name,memory.total,memory.free,driver_version",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            if result.stdout.strip():
                lines.append("\nGPU:")
                for row in result.stdout.strip().splitlines():
                    name, total, free, driver = [part.strip() for part in row.split(",", 3)]
                    lines.append(
                        f"  {name}: {total} MiB total, {free} MiB free, driver {driver}"
                    )
        except Exception as exc:
            lines.append(f"\nGPU query failed: {exc}")
    else:
        lines.append("\nGPU: nvidia-smi not found; AMD/Intel details are not auto-detected.")

    return "\n".join(lines)


class CommandRunner:
    """Run subprocesses without freezing Tkinter and stream merged output."""

    def __init__(self, event_sink: Callable[[dict[str, Any]], None]) -> None:
        self.event_sink = event_sink
        self.processes: set[subprocess.Popen[str]] = set()
        self.lock = threading.Lock()

    def run(
        self,
        command: list[str],
        *,
        name: str,
        cwd: Path | None = None,
        env: dict[str, str] | None = None,
    ) -> None:
        threading.Thread(
            target=self._worker,
            args=(command, name, cwd, env),
            daemon=True,
        ).start()

    def _worker(
        self,
        command: list[str],
        name: str,
        cwd: Path | None,
        env: dict[str, str] | None,
    ) -> None:
        self.event_sink({"kind": "command_started", "name": name, "command": command})
        startupinfo = None
        creationflags = 0
        if os.name == "nt":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            creationflags = subprocess.CREATE_NO_WINDOW

        try:
            process = subprocess.Popen(
                command,
                cwd=str(cwd) if cwd else None,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
                startupinfo=startupinfo,
                creationflags=creationflags,
            )
            with self.lock:
                self.processes.add(process)
            assert process.stdout is not None
            for line in process.stdout:
                self.event_sink(
                    {"kind": "command_output", "name": name, "text": line.rstrip("\n")}
                )
            return_code = process.wait()
            self.event_sink(
                {"kind": "command_finished", "name": name, "return_code": return_code}
            )
        except Exception as exc:
            self.event_sink(
                {"kind": "command_error", "name": name, "error": f"{type(exc).__name__}: {exc}"}
            )
        finally:
            with self.lock:
                self.processes = {p for p in self.processes if p.poll() is None}

    def terminate_all(self) -> None:
        with self.lock:
            processes = list(self.processes)
        for process in processes:
            try:
                process.terminate()
            except Exception:
                pass


def open_folder(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        os.startfile(path)  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])
