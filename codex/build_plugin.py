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


def source_agent_names() -> list[str]:
    names = []
    for path in sorted((REPO_ROOT / "agents").glob("*.md")):
        frontmatter, _ = split_frontmatter(path.read_text(encoding="utf-8"))
        names.append(frontmatter_value(frontmatter, "name"))
    return names


def role_names() -> list[str]:
    names = []
    for path in sorted((REPO_ROOT / "codex" / "contracts" / "roles").glob("*.md")):
        frontmatter, _ = split_frontmatter(path.read_text(encoding="utf-8"))
        names.append(frontmatter_value(frontmatter, "name"))
    return names


SOURCE_AGENT_NAMES = source_agent_names()
ROLE_NAMES = role_names()
AGENT_NAMES = sorted(SOURCE_AGENT_NAMES + ROLE_NAMES, key=len, reverse=True)


# ── Codex token-economy model routing (codex/contracts/routing-policy.md) ──
MODEL_LUNA = "gpt-5.6-luna"
MODEL_TERRA = "gpt-5.6-terra"
MODEL_FRONTIER = "gpt-5.6"

# These pins are a CEILING, not a flat rate. release-sdk PLANs label each task
# `complexity: simple|standard|complex` and the Claude runtime resolves the
# per-spawn tier from it (release_worker_model_for in bin/release-model-lib.sh).
# A label may only DEMOTE from the pin below — never promote past it — and code
# never falls to MODEL_LUNA (that tier is for mechanical/collection agents only).
# tdd-executor is pinned at MODEL_TERRA, which is already the code floor, so the
# label is informational under Codex: it changes no model here, only telemetry.
# See codex/contracts/routing-policy.md § "Per-task complexity routing".
#
# Explicit (model, effort, role_class) per source agent — hand-classified from
# each agent's actual description/tools rather than inferred, because a
# regex heuristic can't reliably tell "mechanical but happens to hold Write"
# (e.g. test-runner saving a result file) apart from a real implementation
# worker. Agents added later without an entry here fall back to
# classify_agent()'s heuristic below — add them here once their tier is known.
AGENT_MODEL_OVERRIDES = {
    "advanced-threat-auditor": (MODEL_FRONTIER, "high", "security_reviewer"),
    "ai-researcher": (MODEL_TERRA, "medium", "docs_researcher"),
    "architecture-reviewer": (MODEL_TERRA, "high", "reviewer"),
    "assumptions-analyzer": (MODEL_TERRA, "medium", "explorer_deep"),
    "code-fixer": (MODEL_TERRA, "medium", "worker"),
    "code-reviewer": (MODEL_TERRA, "high", "reviewer"),
    "codebase-mapper": (MODEL_TERRA, "medium", "explorer_deep"),
    "debugger": (MODEL_TERRA, "high", "explorer_deep"),
    "django-checklist-verifier": (MODEL_LUNA, "low", "tester"),
    "django-discuss-orchestrator": (MODEL_FRONTIER, "high", "planner"),
    "django-security-retro": (MODEL_FRONTIER, "high", "security_reviewer"),
    "doc-classifier": (MODEL_LUNA, "low", "tester"),
    "doc-verifier": (MODEL_TERRA, "medium", "reviewer"),
    "doc-writer": (MODEL_TERRA, "medium", "worker"),
    "eval-auditor": (MODEL_TERRA, "high", "reviewer"),
    "feature-planner": (MODEL_FRONTIER, "high", "planner"),
    "feature-researcher": (MODEL_TERRA, "medium", "explorer_deep"),
    "framework-selector": (MODEL_FRONTIER, "high", "planner"),
    "import-orchestrator": (MODEL_FRONTIER, "high", "planner"),
    "integration-checker": (MODEL_TERRA, "medium", "reviewer"),
    "intel-updater": (MODEL_LUNA, "medium", "explorer_fast"),
    "loop-goal-verifier": (MODEL_TERRA, "high", "reviewer"),
    "milestone-auditor": (MODEL_TERRA, "high", "reviewer"),
    "nyquist-auditor": (MODEL_LUNA, "low", "tester"),
    "pattern-mapper": (MODEL_LUNA, "medium", "explorer_fast"),
    "phase-verifier": (MODEL_TERRA, "high", "reviewer"),
    "plan-checker": (MODEL_TERRA, "high", "reviewer"),
    "react-security-retro": (MODEL_FRONTIER, "high", "security_reviewer"),
    "react-ui-auditor": (MODEL_TERRA, "medium", "reviewer"),
    "react-ui-checker": (MODEL_TERRA, "medium", "reviewer"),
    "react-ui-researcher": (MODEL_TERRA, "medium", "worker"),
    "security-auditor": (MODEL_FRONTIER, "high", "security_reviewer"),
    "spec-clarifier": (MODEL_TERRA, "medium", "worker"),
    "tdd-executor": (MODEL_TERRA, "medium", "worker"),
    "test-auditor": (MODEL_TERRA, "medium", "worker"),
    "test-discover": (MODEL_LUNA, "low", "tester"),
    "test-runner": (MODEL_LUNA, "low", "tester"),
    "uat-conductor": (MODEL_TERRA, "medium", "worker"),
    "wave-executor": (MODEL_FRONTIER, "high", "planner"),
}

# Output token budget per role_class — codex/contracts/routing-policy.md §9.
BUDGET_BY_CLASS = {
    "explorer_fast": 700,
    "explorer_deep": 1200,
    "planner": 1500,
    "worker_lite": 700,
    "worker": 1200,
    "worker_complex": 1500,
    "tester": 700,
    "reviewer": 1200,
    "security_reviewer": 1500,
    "docs_researcher": 700,
    "handoff_writer": 500,
    "agents_md_builder": 1200,
}

# Fixed model/effort for the 12 Codex-only generic roles (codex/contracts/roles/).
GENERIC_ROLE_SPECS = {
    "explorer-fast": (MODEL_LUNA, "low"),
    "explorer-deep": (MODEL_TERRA, "medium"),
    "planner": (MODEL_FRONTIER, "high"),
    "worker-lite": (MODEL_LUNA, "low"),
    "worker": (MODEL_TERRA, "medium"),
    "worker-complex": (MODEL_FRONTIER, "high"),
    "tester": (MODEL_LUNA, "low"),
    "reviewer": (MODEL_TERRA, "high"),
    "security-reviewer": (MODEL_FRONTIER, "high"),
    "docs-researcher": (MODEL_LUNA, "medium"),
    "handoff-writer": (MODEL_LUNA, "low"),
    "agents-md-builder": (MODEL_TERRA, "medium"),
}


def classify_agent(name: str, frontmatter: str, description: str, body: str) -> tuple[str, str, str]:
    """Return (model, reasoning_effort, role_class) for a specialized release agent.

    Every agent shipped today has an explicit AGENT_MODEL_OVERRIDES entry —
    the heuristic below only covers an agent added later without one yet.
    """
    if name in AGENT_MODEL_OVERRIDES:
        return AGENT_MODEL_OVERRIDES[name]

    tools = ""
    try:
        tools = frontmatter_value(frontmatter, "tools")
    except ValueError:
        pass
    has_write = "write" in tools.lower() or "edit" in tools.lower()
    text = f"{description} {body[:1500]}".lower()

    if re.search(r"adversarial|goal-backward|security|threat", text):
        return (MODEL_FRONTIER, "high", "security_reviewer" if "security" in text or "threat" in text else "reviewer")
    if re.search(r"review|audit|check|verif", text):
        return (MODEL_TERRA, "high", "reviewer")
    if has_write:
        return (MODEL_TERRA, "medium", "worker")
    return (MODEL_LUNA, "medium", "explorer_deep")


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


def write_agent_toml(
    output: Path,
    contract: str,
    name: str,
    description: str,
    model: str,
    effort: str,
    budget: int,
    role_class: str,
    body: str,
    source_label: str,
) -> dict:
    instructions = f"{contract}\n\n{transform_common(body).lstrip()}"
    if "'''" in instructions:
        raise ValueError(f"{source_label}: TOML literal delimiter collision")
    toml = (
        f"name = {json.dumps(name, ensure_ascii=False)}\n"
        f"description = {json.dumps(description, ensure_ascii=False)}\n"
        f"model = {json.dumps(model, ensure_ascii=False)}\n"
        f"reasoning_effort = {json.dumps(effort, ensure_ascii=False)}\n"
        f"output_token_budget = {budget}\n"
        f"role_class = {json.dumps(role_class, ensure_ascii=False)}\n"
        f"developer_instructions = '''\n{instructions.rstrip()}\n'''\n"
    )
    write_text(output / "agents" / f"{name}.toml", toml)
    return {
        "name": name,
        "source": source_label,
        "role_class": role_class,
        "model": model,
        "reasoning_effort": effort,
        "output_token_budget": budget,
        "description": description,
    }


def build_agents(output: Path) -> None:
    if set(SOURCE_AGENT_NAMES) & set(ROLE_NAMES):
        raise ValueError(
            f"agent/role name collision: {set(SOURCE_AGENT_NAMES) & set(ROLE_NAMES)}"
        )

    contract = (REPO_ROOT / "codex" / "contracts" / "agent-contract.md").read_text(encoding="utf-8").rstrip()
    index = []

    for source in sorted((REPO_ROOT / "agents").glob("*.md")):
        frontmatter, body = split_frontmatter(source.read_text(encoding="utf-8"))
        source_name = frontmatter_value(frontmatter, "name")
        description = transform_common(frontmatter_value(frontmatter, "description"))
        name = f"release-{source_name}"
        model, effort, role_class = classify_agent(source_name, frontmatter, description, body)
        budget = BUDGET_BY_CLASS[role_class]
        index.append(
            write_agent_toml(output, contract, name, description, model, effort, budget, role_class, body, source.name)
        )

    for source in sorted((REPO_ROOT / "codex" / "contracts" / "roles").glob("*.md")):
        frontmatter, body = split_frontmatter(source.read_text(encoding="utf-8"))
        source_name = frontmatter_value(frontmatter, "name")
        description = transform_common(frontmatter_value(frontmatter, "description"))
        name = f"release-{source_name}"
        model, effort = GENERIC_ROLE_SPECS[source_name]
        role_class = source_name.replace("-", "_")
        budget = BUDGET_BY_CLASS[role_class]
        index.append(
            write_agent_toml(output, contract, name, description, model, effort, budget, role_class, body, source.name)
        )

    write_text(output / "agents" / "index.json", json.dumps(index, ensure_ascii=False, indent=2) + "\n")


def build_manifest(output: Path) -> None:
    legacy = json.loads((REPO_ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    base_version = legacy["version"].split("+", 1)[0]
    manifest = {
        "name": "release",
        "version": f"{base_version}+codex.2",
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
    shutil.copy2(REPO_ROOT / "codex" / "runtime" / "agents-md-guard.js", output / "hooks" / "release-agents-md-guard.js")
    shutil.copy2(REPO_ROOT / "codex" / "runtime" / "hooks.json", output / "hooks" / "hooks.json")

    copy_tree(REPO_ROOT / "bin", output / "bin", transform_bin)
    shutil.copy2(REPO_ROOT / "codex" / "runtime" / "install_codex_agents.py", output / "bin" / "install-codex-agents.py")
    (output / "bin" / "install-codex-agents.py").chmod(0o755)

    copy_tree(REPO_ROOT / "templates", output / "templates", lambda _path, text: transform_common(text))
    write_text(
        output / "templates" / "codex-config.toml",
        transform_common((REPO_ROOT / "codex" / "runtime" / "config.toml").read_text(encoding="utf-8")),
    )
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
