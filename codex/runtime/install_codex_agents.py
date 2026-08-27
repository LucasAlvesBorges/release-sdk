#!/usr/bin/env python3
"""Install generated release-sdk agents into Codex without touching Claude state."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Codex ships Python 3.11+
    tomllib = None


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def default_target() -> Path:
    codex_root = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    return codex_root / "agents"


def validate_agent(path: Path) -> dict[str, str]:
    if not path.name.startswith("release-") or path.suffix != ".toml":
        raise ValueError(f"unexpected agent file: {path.name}")
    if tomllib is None:
        raise RuntimeError("Python 3.11+ is required to validate agent TOML")
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    for field in ("name", "description", "developer_instructions"):
        if not isinstance(data.get(field), str) or not data[field].strip():
            raise ValueError(f"{path.name}: missing {field}")
    if data["name"] != path.stem:
        raise ValueError(f"{path.name}: name must match filename")
    return data


def atomic_copy(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(source.read_bytes())
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plugin-root", type=Path)
    parser.add_argument("--target-dir", type=Path, default=default_target())
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--install", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()

    plugin_root = (args.plugin_root or Path(__file__).resolve().parents[1]).resolve()
    source_dir = plugin_root / "agents"
    target_dir = args.target_dir.expanduser().resolve()

    sources = sorted(source_dir.glob("release-*.toml"))
    if not sources:
        print(json.dumps({"status": "error", "reason": "no generated agents"}))
        return 2

    for source in sources:
        validate_agent(source)

    stale = []
    for source in sources:
        target = target_dir / source.name
        if not target.exists() or digest(source) != digest(target):
            stale.append(source)

    if args.check:
        status = "ready" if not stale else "stale"
        print(
            json.dumps(
                {
                    "status": status,
                    "agents": len(sources),
                    "stale": [path.name for path in stale],
                    "target": str(target_dir),
                },
                ensure_ascii=False,
            )
        )
        return 0 if not stale else 1

    for source in stale:
        atomic_copy(source, target_dir / source.name)

    # Retired SDK-owned agents must not survive an upgrade merely because the
    # current package no longer ships a source file for them. Keep this list
    # explicit so the installer never deletes unrelated user agents.
    retired_names = {"release-django-discuss-orchestrator.toml"}
    removed = []
    for name in sorted(retired_names):
        target = target_dir / name
        if target.is_file():
            target.unlink()
            removed.append(name)

    print(
        json.dumps(
            {
                "status": "installed",
                "agents": len(sources),
                "updated": len(stale),
                "removed": removed,
                "target": str(target_dir),
                "next": "start a new Codex task",
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
