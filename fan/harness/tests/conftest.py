"""Shared test fixtures: isolated workspace, config, harness bits."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sidelearner.config import Config  # noqa: E402
from sidelearner.router.embeddings import TokenHashEmbedder  # noqa: E402


@pytest.fixture()
def workspace(tmp_path):
    return tmp_path


@pytest.fixture()
def config(workspace):
    return Config(
        {
            "workspace": str(workspace),
            "vault_dir": str(workspace / "vault"),
            "memory": {"db": str(workspace / "memory.db")},
            "providers": {},
            "perception": {"screen": {"enabled": False}, "window": {"enabled": False}, "audio": {"enabled": False}, "camera": {"enabled": False}},
            "business": {"workflow_dirs": []},
        },
        workspace=workspace,
    )


@pytest.fixture()
def embedder():
    return TokenHashEmbedder()
