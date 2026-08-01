#!/usr/bin/env python3
"""Build an isolated, deterministic Codex edition of release-sdk.

The Claude Code source tree is read-only input. Generated output lives under
plugins/release so the two runtimes never share mutable configuration.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import stat
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "plugins" / "release"
GENERATED_MARKER = ".release-codex-generated"
TEXT_SUFFIXES = {".md", ".sh", ".js", ".json", ".html", ".txt", ".yml", ".yaml", ".toml"}


def split_frontmatter(text: str) -> tuple[str, str]:
    if not text.startswith("---\n"):
        return "", text
    end = text.find("\n---\n", 4)
    if end < 0:
        raise ValueError("unterminated frontmatter")
    return text[4:end], text[end + 5 :]


def frontmatter_value(frontmatter: str, key: str) -> str:
    lines = frontmatter.splitlines()
    for index, line in enumerate(lines):
        if not line.startswith(f"{key}:"):
            continue
        value = line.split(":", 1)[1].strip()
        if value in {">", "|"}:
            collected = []
            for following in lines[index + 1 :]:
                if following and not following.startswith((" ", "\t")):
                    break
                collected.append(following.strip())
            return " ".join(collected).strip()
        return value.strip('"\'')
    raise ValueError(f"missing frontmatter key: {key}")


def agent_names() -> list[str]:
    names = []
    for path in sorted((REPO_ROOT / "agents").glob("*.md")):
        frontmatter, _ = split_frontmatter(path.read_text(encoding="utf-8"))
        names.append(frontmatter_value(frontmatter, "name"))
    return sorted(names, key=len, reverse=True)


AGENT_NAMES = agent_names()


def transform_common(text: str) -> str:
    replacements = [
        ("CLAUDE_PLUGIN_ROOT", "RELEASE_PLUGIN_ROOT"),
        ("CLAUDE_PLUGIN_DATA", "RELEASE_PLUGIN_DATA"),
        ("CLAUDE_PROJECT_DIR", "CODEX_PROJECT_DIR"),
        ("CLAUDE_EFFORT", "CODEX_REASONING_EFFORT"),
        ("~/.claude/plugins/cache/release-sdk/release", "${CODEX_HOME:-$HOME/.codex}/plugins/cache/release-sdk/release"),
        ("~/.claude/plugins/cache/release-sdk", "${CODEX_HOME:-$HOME/.codex}/plugins/cache/release-sdk"),
        ("~/.claude/token-tracker", "${CODEX_HOME:-$HOME/.codex}/release-sdk/token-tracker"),
        ("$HOME/.claude", "${CODEX_HOME:-$HOME/.codex}"),
        (".claude/skills/", ".agents/skills/"),
        (".claude-plugin-cache", ".codex-release-cache"),
        (".claude-plugin/", ".codex-plugin/"),
        ("CLAUDE.md", "AGENTS.md"),
        ("Claude Code", "Codex"),
        ("Claude session", "Codex session"),
        ("Claude's discretion", "Codex's discretion"),
        ("Claude Security Auditor", "Codex Security Auditor"),
        ("&& claude", "&& codex"),
        ("Generated with [Claude Code](https://claude.com/claude-code)", "Generated with Codex"),
        ("Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>", "Co-Authored-By: Codex <noreply@openai.com>"),
    ]
    for source, target in replacements:
        text = text.replace(source, target)

    for name in AGENT_NAMES:
        text = text.replace(f"release:{name}", f"release-{name}")

    return text


def transform_context_monitor(text: str) -> str:
    start = text.find("function resolveCacheDir() {")
    end = text.find("\nlet input = '';", start)
    if start < 0 or end < 0:
        raise ValueError("release-context-monitor.js layout changed")
    replacement = """function resolveCacheDir() {
  const primary = process.env.PLUGIN_DATA
    ? path.join(process.env.PLUGIN_DATA, 'context-monitor')
    : path.join('/tmp', 'release-sdk-codex-context-monitor');
  try {
    fs.mkdirSync(primary, { recursive: true });
  } catch {}
  return primary;
}
"""
    text = text[:start] + replacement + text[end:]
    return text.replace("so Claude can proactively summarize", "so Codex can proactively summarize")


def transform_hook(path: Path, text: str) -> str:
    text = transform_common(text)
    if path.name == "release-context-monitor.js":
        text = transform_context_monitor(text)
    if path.name == "release-token-collector.js":
        old = "const STATE_DIR = path.join(os.homedir(), '.claude', 'token-tracker', 'cursors');"
        new = (
            "const STATE_DIR = path.join(process.env.PLUGIN_DATA || "
            "path.join(os.homedir(), '.codex', 'release-sdk'), 'token-tracker', 'cursors');"
        )
        if old not in path.read_text(encoding="utf-8"):
            raise ValueError("release-token-collector.js state path changed")
        # transform_common already changed the old path; replace the transformed shape.
        transformed_old = "const STATE_DIR = path.join(os.homedir(), '.claude', 'token-tracker', 'cursors');"
        if transformed_old in text:
            text = text.replace(transformed_old, new)
        else:
            text = re.sub(
                r"const STATE_DIR = path\.join\(os\.homedir\(\), '[^']+', 'token-tracker', 'cursors'\);",
                new,
                text,
                count=1,
            )
    return text


def transform_bin(path: Path, text: str) -> str:
    text = transform_common(text)
    if path.name == "release-token-worker.js":
        text = re.sub(
            r"const DATA_DIR = path\.join\(os\.homedir\(\), '[^']+', 'token-tracker'\);",
            "const DATA_DIR = process.env.RELEASE_SDK_DATA_DIR || path.join(os.homedir(), '.codex', 'release-sdk', 'token-tracker');",
            text,
            count=1,
        )
    return text


def write_text(path: Path, text: str, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    if executable:
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def copy_tree(source: Path, target: Path, transform) -> None:
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        destination = target / relative
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        if path.suffix.lower() in TEXT_SUFFIXES or path.name == "SKILL.md":
            text = transform(path, path.read_text(encoding="utf-8"))
            executable = bool(path.stat().st_mode & stat.S_IXUSR)
            write_text(destination, text, executable=executable)
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)


def transform_skill(path: Path, text: str) -> str:
    text = transform_common(text)
    if path.name != "SKILL.md":
        return text
    if path.parent.name == "auto":
        aliases = {
            "`gsd-planner` → `release-planner`": "`gsd-planner` → `release-feature-planner`",
            "`gsd-executor` → `release-executor`": "`gsd-executor` → `release-tdd-executor`",
            "`gsd-verifier` → `release-verifier`": "`gsd-verifier` → `release-phase-verifier`",
            "`gsd-phase-researcher` → `release-phase-researcher`": "`gsd-phase-researcher` → `release-feature-researcher`",
            "`gsd-roadmapper` → `release-roadmapper`": "`gsd-roadmapper` → `release:new-milestone` (skill; no direct agent spawn)",
        }
        for source, target in aliases.items():
            text = text.replace(source, target)
    frontmatter, body = split_frontmatter(text)
    contract = (REPO_ROOT / "codex" / "contracts" / "skill-contract.md").read_text(encoding="utf-8")
    return f"---\n{frontmatter}\n---\n\n{contract.rstrip()}\n\n{body.lstrip()}"


def fallback_role(frontmatter: str, body: str) -> str:
    tools = ""
    try:
        tools = frontmatter_value(frontmatter, "tools")
    except ValueError:
        pass
    lowered = (frontmatter + body[:2500]).lower()
    if "write" in tools.lower() or "edit" in tools.lower():
        return "worker"
    if any(word in lowered for word in ("orchestrat", "planner", "checker", "verifier", "auditor")):
        return "default"
    return "explorer"


def build_agents(output: Path) -> None:
    contract = (REPO_ROOT / "codex" / "contracts" / "agent-contract.md").read_text(encoding="utf-8").rstrip()
    index = []
    for source in sorted((REPO_ROOT / "agents").glob("*.md")):
        frontmatter, body = split_frontmatter(source.read_text(encoding="utf-8"))
        source_name = frontmatter_value(frontmatter, "name")
        description = transform_common(frontmatter_value(frontmatter, "description"))
        name = f"release-{source_name}"
        role = fallback_role(frontmatter, body)
        instructions = f"{contract}\n\n{transform_common(body).lstrip()}"
        if "'''" in instructions:
            raise ValueError(f"{source}: TOML literal delimiter collision")
        toml = (
            f"name = {json.dumps(name, ensure_ascii=False)}\n"
            f"description = {json.dumps(description, ensure_ascii=False)}\n"
            f"developer_instructions = '''\n{instructions.rstrip()}\n'''\n"
        )
        write_text(output / "agents" / f"{name}.toml", toml)
        index.append({"name": name, "source": source.name, "fallback": role, "description": description})
    write_text(output / "agents" / "index.json", json.dumps(index, ensure_ascii=False, indent=2) + "\n")


def build_manifest(output: Path) -> None:
    legacy = json.loads((REPO_ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    base_version = legacy["version"].split("+", 1)[0]
    manifest = {
        "name": "release",
        "version": f"{base_version}+codex.1",
        "description": "Codex-native full-stack delivery workflows for Django, React, and React Native with specialized subagents.",
        "author": {
            "name": legacy["author"]["name"],
            "email": legacy["author"]["email"],
            "url": "https://github.com/LucasAlvesBorges",
        },
        "homepage": legacy["homepage"],
        "repository": legacy["repository"],
        "license": legacy["license"],
        "keywords": legacy["keywords"],
        "skills": "./skills/",
        "interface": {
            "displayName": "Release SDK",
            "shortDescription": "Structured delivery workflows with Codex subagents",
            "longDescription": "Plan, implement, review, secure, and verify Django, React, and React Native work using Codex-native skills and specialized subagents.",
            "developerName": legacy["author"]["name"],
            "category": "Developer Tools",
            "capabilities": ["Read", "Write"],
            "websiteURL": legacy["homepage"],
            "defaultPrompt": [
                "Set up the Release SDK subagents for Codex.",
                "Use Release SDK to show project status and the next step.",
                "Use Release SDK to plan and execute the active phase.",
            ],
            "brandColor": "#10B981",
        },
    }
    write_text(output / ".codex-plugin" / "plugin.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def prepare_output(output: Path) -> None:
    output = output.resolve()
    if output.exists():
        marker = output / GENERATED_MARKER
        if not marker.exists():
            raise ValueError(f"refusing to replace non-generated directory: {output}")
        shutil.rmtree(output)
    output.mkdir(parents=True)
    write_text(output / GENERATED_MARKER, "generated by codex/build_plugin.py\n")


def build(output: Path) -> None:
    prepare_output(output)
    build_manifest(output)

    copy_tree(REPO_ROOT / "skills", output / "skills", transform_skill)
    setup_source = REPO_ROOT / "codex" / "skills" / "setup-codex" / "SKILL.md"
    write_text(output / "skills" / "setup-codex" / "SKILL.md", setup_source.read_text(encoding="utf-8"))

    build_agents(output)

    copy_tree(REPO_ROOT / "hooks", output / "hooks", transform_hook)
    shutil.copy2(REPO_ROOT / "codex" / "runtime" / "codex-edit-adapter.js", output / "hooks" / "codex-edit-adapter.js")
    shutil.copy2(REPO_ROOT / "codex" / "runtime" / "hooks.json", output / "hooks" / "hooks.json")

    copy_tree(REPO_ROOT / "bin", output / "bin", transform_bin)
    shutil.copy2(REPO_ROOT / "codex" / "runtime" / "install_codex_agents.py", output / "bin" / "install-codex-agents.py")
    (output / "bin" / "install-codex-agents.py").chmod(0o755)

    copy_tree(REPO_ROOT / "templates", output / "templates", lambda _path, text: transform_common(text))
    shutil.copy2(REPO_ROOT / "LICENSE", output / "LICENSE")

    readme = """# Release SDK for Codex

This directory is generated by `codex/build_plugin.py`. Do not edit it by hand.

The Codex package is isolated from the Claude Code package at the repository
root. Run the `release:setup-codex` skill after installation, then start a new
Codex task to load the generated `release-*` custom subagents.
"""
    write_text(output / "README.md", readme)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    build(args.output)
    print(f"Built Codex plugin: {args.output.resolve()}")


if __name__ == "__main__":
    main()
