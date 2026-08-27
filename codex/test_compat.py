#!/usr/bin/env python3
from __future__ import annotations

import json
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PLUGIN = REPO_ROOT / "plugins" / "release"


def tree_digest(roots: list[Path]) -> str:
    result = hashlib.sha256()
    files = []
    for root in roots:
        if root.is_file():
            files.append(root)
        elif root.exists():
            files.extend(path for path in root.rglob("*") if path.is_file())
    for path in sorted(files):
        result.update(str(path.relative_to(REPO_ROOT)).encode())
        result.update(path.read_bytes())
    return result.hexdigest()


class CodexCompatibilityTests(unittest.TestCase):
    def test_manifest_and_marketplace(self) -> None:
        manifest = json.loads((PLUGIN / ".codex-plugin" / "plugin.json").read_text())
        marketplace = json.loads((REPO_ROOT / ".agents" / "plugins" / "marketplace.json").read_text())
        self.assertEqual(manifest["name"], "release")
        self.assertEqual(manifest["skills"], "./skills/")
        self.assertNotIn("hooks", manifest)
        self.assertEqual(marketplace["plugins"][0]["source"]["path"], "./plugins/release")
        self.assertEqual(marketplace["plugins"][0]["policy"]["installation"], "AVAILABLE")

    def test_all_skills_are_generated_with_contract(self) -> None:
        source = sorted((REPO_ROOT / "skills").glob("*/SKILL.md"))
        generated = sorted((PLUGIN / "skills").glob("*/SKILL.md"))
        self.assertEqual(len(generated), len(source) + 1)
        for path in generated:
            text = path.read_text()
            self.assertTrue(text.startswith("---\n"), path)
            if path.parent.name != "setup-codex":
                self.assertIn("Codex runtime contract", text, path)

    def test_all_agents_are_valid_toml(self) -> None:
        source = sorted((REPO_ROOT / "agents").glob("*.md"))
        roles = sorted((REPO_ROOT / "codex" / "contracts" / "roles").glob("*.md"))
        generated = sorted((PLUGIN / "agents").glob("release-*.toml"))
        self.assertEqual(len(generated), len(source) + len(roles))
        valid_models = {"gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6"}
        valid_efforts = {"low", "medium", "high", "xhigh"}
        for path in generated:
            data = tomllib.loads(path.read_text())
            self.assertEqual(data["name"], path.stem)
            self.assertIn("codex_runtime_contract", data["developer_instructions"])
            self.assertIn(data["model"], valid_models, path)
            self.assertIn(data["reasoning_effort"], valid_efforts, path)
            self.assertIsInstance(data["output_token_budget"], int)
            self.assertGreater(data["output_token_budget"], 0)
            self.assertTrue(data["role_class"], path)

    def test_generic_roles_present(self) -> None:
        expected = {
            "explorer-fast",
            "explorer-deep",
            "planner",
            "worker-lite",
            "worker",
            "worker-complex",
            "tester",
            "reviewer",
            "security-reviewer",
            "docs-researcher",
            "handoff-writer",
            "agents-md-builder",
        }
        for role in expected:
            path = PLUGIN / "agents" / f"release-{role}.toml"
            self.assertTrue(path.exists(), path)
            data = tomllib.loads(path.read_text())
            self.assertEqual(data["role_class"], role.replace("-", "_"))

    def test_config_template_shipped(self) -> None:
        path = PLUGIN / "templates" / "codex-config.toml"
        self.assertTrue(path.exists())
        data = tomllib.loads(path.read_text())
        self.assertEqual(data["agents_md"]["mode"], "strict")
        self.assertTrue(data["agents_md"]["required"])
        self.assertEqual(data["routing"]["default_spawn"], False)
        self.assertIn("worker_output_tokens", data["budgets"])

    def test_generated_runtime_has_no_claude_state_paths(self) -> None:
        forbidden = ("$HOME/.claude", "CLAUDE_PLUGIN_ROOT", "CLAUDE_PROJECT_DIR")
        for root in (PLUGIN / "skills", PLUGIN / "agents", PLUGIN / "hooks", PLUGIN / "bin", PLUGIN / "templates"):
            for path in root.rglob("*"):
                if not path.is_file():
                    continue
                try:
                    text = path.read_text()
                except UnicodeDecodeError:
                    continue
                for value in forbidden:
                    self.assertNotIn(value, text, f"{value} in {path}")

        for root in (PLUGIN / "hooks", PLUGIN / "bin"):
            for path in root.rglob("*"):
                if path.is_file() and path.suffix in {".js", ".sh", ".py"}:
                    self.assertNotIn(".claude", path.read_text(), path)

    def test_build_is_deterministic_and_claude_sources_are_read_only(self) -> None:
        claude_roots = [
            REPO_ROOT / ".claude-plugin",
            REPO_ROOT / "skills",
            REPO_ROOT / "agents",
            REPO_ROOT / "hooks",
            REPO_ROOT / "bin",
            REPO_ROOT / "templates",
        ]
        source_before = tree_digest(claude_roots)
        plugin_before = tree_digest([PLUGIN])
        subprocess.run([sys.executable, str(REPO_ROOT / "codex" / "build_plugin.py")], check=True, capture_output=True)
        self.assertEqual(source_before, tree_digest(claude_roots))
        self.assertEqual(plugin_before, tree_digest([PLUGIN]))

    def test_agent_installer_is_scoped_and_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "agents"
            target.mkdir()
            sentinel = target / "unrelated-agent.toml"
            sentinel.write_text('name = "unrelated"\n')
            command = [
                sys.executable,
                str(PLUGIN / "bin" / "install-codex-agents.py"),
                "--plugin-root",
                str(PLUGIN),
                "--target-dir",
                str(target),
                "--install",
            ]
            first = subprocess.run(command, check=True, capture_output=True, text=True)
            second = subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual(json.loads(first.stdout)["updated"], len(list((PLUGIN / "agents").glob("release-*.toml"))))
            self.assertEqual(json.loads(second.stdout)["updated"], 0)
            self.assertEqual(sentinel.read_text(), 'name = "unrelated"\n')

    def test_apply_patch_adapter_reaches_consolidated_edit_guard(self) -> None:
        if not shutil.which("node"):
            self.skipTest("node unavailable")
        payload = {
            "tool_name": "apply_patch",
            "tool_input": {
                "command": "*** Begin Patch\n*** Update File: src/components/Login.tsx\n@@\n+localStorage.setItem('auth_token', token)\n*** End Patch"
            },
        }
        result = subprocess.run(
            [
                "node",
                str(PLUGIN / "hooks" / "codex-edit-adapter.js"),
                str(PLUGIN / "hooks" / "release-edit-guard.js"),
            ],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            check=True,
        )
        output = json.loads(result.stdout)
        self.assertIn("AUTH_TOKEN_STORAGE", output["hookSpecificOutput"]["additionalContext"])

    def test_runtime_hooks_use_one_edit_scan_and_no_per_call_context_monitor(self) -> None:
        runtime = json.loads((PLUGIN / "hooks" / "hooks.json").read_text())
        serialized = json.dumps(runtime)
        self.assertEqual(serialized.count("release-edit-guard.js"), 1)
        self.assertNotIn("django-workflow-guard.js", serialized)
        self.assertNotIn("react-security-guard.js", serialized)
        self.assertNotIn("release-context-monitor.js", serialized)

    def test_legacy_hooks_are_not_shipped(self) -> None:
        retired = {
            "django-prompt-guard.js",
            "django-tenant-scope-check.sh",
            "django-workflow-guard.js",
            "react-security-guard.js",
            "react-workflow-guard.js",
            "release-context-monitor.js",
            "release-read-injection-scanner.js",
        }
        shipped = {path.name for path in (PLUGIN / "hooks").iterdir()}
        self.assertTrue(retired.isdisjoint(shipped), retired & shipped)

    def test_token_collector_advances_by_byte_offset(self) -> None:
        if not shutil.which("node"):
            self.skipTest("node unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            transcript = root / "transcript.jsonl"
            transcript.write_text(
                json.dumps({
                    "type": "user",
                    "message": {"content": "Base directory for this skill: /skills/quick\n# /release:quick"},
                }) + "\n" +
                json.dumps({
                    "type": "assistant", "uuid": "u1", "timestamp": "2026-01-01T00:00:00Z",
                    "message": {"model": "claude-sonnet-4-6", "usage": {"input_tokens": 10, "output_tokens": 2}},
                }) + "\n"
            )
            environment = os.environ.copy()
            environment["PLUGIN_DATA"] = str(root / "plugin-data")
            environment["RELEASE_TOKEN_PORT"] = "9"
            payload = {"session_id": "incremental-test", "transcript_path": str(transcript), "cwd": str(root)}
            command = ["node", str(PLUGIN / "hooks" / "release-token-collector.js")]
            subprocess.run(command, input=json.dumps(payload), text=True, check=True, env=environment)

            cursor_path = root / "plugin-data" / "token-tracker" / "cursors" / "incremental-test.json"
            first = json.loads(cursor_path.read_text())
            self.assertEqual(first["last_uuid"], "u1")
            self.assertEqual(first["byte_offset"], transcript.stat().st_size)
            self.assertEqual(first["skill"], "release:quick")

            with transcript.open("a") as stream:
                stream.write(json.dumps({
                    "type": "assistant", "uuid": "u2", "timestamp": "2026-01-01T00:00:01Z",
                    "message": {"model": "claude-opus-4-8", "usage": {"input_tokens": 5, "output_tokens": 1}},
                }) + "\n")
            subprocess.run(command, input=json.dumps(payload), text=True, check=True, env=environment)
            second = json.loads(cursor_path.read_text())
            self.assertEqual(second["last_uuid"], "u2")
            self.assertGreater(second["byte_offset"], first["byte_offset"])

    def test_token_collector_attributes_subagent_context(self) -> None:
        if not shutil.which("node"):
            self.skipTest("node unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            transcript = root / "agent-reviewer.jsonl"
            transcript.write_text(json.dumps({
                "type": "assistant",
                "uuid": "agent-u1",
                "timestamp": "2026-01-01T00:00:00Z",
                "attributionSkill": "release:review",
                "attributionAgent": "release:code-reviewer",
                "agentId": "agent-42",
                "message": {
                    "model": "claude-sonnet-4-6",
                    "content": [{"type": "text", "text": "phase_number: 7 C3"}],
                    "usage": {"input_tokens": 10, "output_tokens": 2},
                },
            }) + "\n")
            environment = os.environ.copy()
            environment["PLUGIN_DATA"] = str(root / "plugin-data")
            environment["RELEASE_TOKEN_PORT"] = "9"
            payload = {"session_id": "subagent-test", "transcript_path": str(transcript), "cwd": str(root)}
            subprocess.run(
                ["node", str(PLUGIN / "hooks" / "release-token-collector.js")],
                input=json.dumps(payload), text=True, check=True, env=environment,
            )
            cursor = json.loads((
                root / "plugin-data" / "token-tracker" / "cursors" /
                "subagent-test-agent-reviewer.json"
            ).read_text())
            self.assertEqual(cursor["skill"], "release:review")
            self.assertEqual(cursor["agent"], "release:code-reviewer")
            self.assertEqual(cursor["phase"], "07")
            self.assertEqual(cursor["complexity"], "C3")
            self.assertEqual(cursor["mode"], "agent")

    def _run_agents_md_guard(self, cwd: Path, file_path: str) -> subprocess.CompletedProcess:
        payload = {"tool_name": "Write", "tool_input": {"file_path": file_path}, "cwd": str(cwd)}
        return subprocess.run(
            ["node", str(PLUGIN / "hooks" / "release-agents-md-guard.js")],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
        )

    def test_agents_md_guard_blocks_when_missing(self) -> None:
        if not shutil.which("node") or not shutil.which("git"):
            self.skipTest("node/git unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            result = self._run_agents_md_guard(root, str(root / "app.py"))
            self.assertEqual(result.returncode, 2, result.stderr)
            output = json.loads(result.stdout)
            self.assertEqual(output["decision"], "block")
            self.assertEqual(output["code"], "AGENTS_MD_REQUIRED")

    def test_agents_md_guard_allows_creating_agents_md_itself(self) -> None:
        if not shutil.which("node") or not shutil.which("git"):
            self.skipTest("node/git unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            result = self._run_agents_md_guard(root, str(root / "AGENTS.md"))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "")

    def test_agents_md_guard_allows_when_agents_md_exists(self) -> None:
        if not shutil.which("node") or not shutil.which("git"):
            self.skipTest("node/git unavailable")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            (root / "AGENTS.md").write_text("# AGENTS\n")
            result = self._run_agents_md_guard(root, str(root / "app.py"))
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
