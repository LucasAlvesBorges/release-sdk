#!/usr/bin/env python3
from __future__ import annotations

import json
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import tomllib
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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
        claude_manifest = json.loads((REPO_ROOT / ".claude-plugin" / "plugin.json").read_text())
        claude_marketplace = json.loads((REPO_ROOT / ".claude-plugin" / "marketplace.json").read_text())
        self.assertEqual(manifest["name"], "release")
        self.assertEqual(claude_marketplace["plugins"][0]["version"], claude_manifest["version"])
        self.assertEqual(manifest["version"], f'{claude_manifest["version"]}+codex.3')
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

    def test_plan_owns_gray_area_preflight_and_discuss_is_removed(self) -> None:
        self.assertFalse((REPO_ROOT / "skills" / "discuss" / "SKILL.md").exists())
        self.assertFalse((REPO_ROOT / "agents" / "django-discuss-orchestrator.md").exists())
        self.assertFalse((PLUGIN / "skills" / "discuss" / "SKILL.md").exists())
        self.assertFalse((PLUGIN / "agents" / "release-django-discuss-orchestrator.toml").exists())

        plan = (REPO_ROOT / "skills" / "plan" / "SKILL.md").read_text()
        planner = (REPO_ROOT / "agents" / "feature-planner.md").read_text()
        self.assertLess(plan.index("## Decision preflight"), plan.index("Spawn it exactly once"))
        for contract in (
            "before any PLAN write",
            "If `{NN}-SPEC.md` is absent",
            "do not invoke another skill or planner",
            "at most three unanswered, decision-changing questions per batch",
            "stable `D-XX [LOCKED]`",
            "no HIGH questions and no MED",
            "Do not create or revise PLAN",
            "auth/authorization and tenancy",
            "async side effects, failure/idempotency and concurrency",
            "volume, performance and",
            "loading/empty/error states",
            "fullstack API/auth/error handoff",
        ):
            self.assertIn(contract, plan)
        self.assertIn("decisions_settled: true (required)", planner)
        self.assertIn("refuse to write or revise PLAN", planner)

        active_files = [
            *(REPO_ROOT / "skills").glob("*/SKILL.md"),
            *(REPO_ROOT / "agents").glob("*.md"),
            *(REPO_ROOT / "templates").glob("*.md"),
            REPO_ROOT / "README.md",
            REPO_ROOT / "README.en.md",
        ]
        for path in active_files:
            text = path.read_text()
            self.assertNotIn("/release:discuss", text, path)
            self.assertNotIn("/django:discuss", text, path)

    def test_execute_uses_existing_dev_harness_without_provisioning(self) -> None:
        source = (REPO_ROOT / "skills" / "execute" / "SKILL.md").read_text()
        generated = (PLUGIN / "skills" / "execute" / "SKILL.md").read_text()
        for contract in (
            "checkout already mounted by the project's development",
            "test_harness: external",
            "managed test environments are disabled",
            "RELEASE_EXEC_PREFIX",
            "Never call `execenv_phase_prepare`, `execenv_provision`, `execenv_teardown`",
            "run_gate_cached \"$ROOT\" full",
            "There is no environment cleanup because the SDK created none.",
        ):
            self.assertIn(contract, source)
            self.assertIn(contract, generated)
        for obsolete in (
            "harness_scope: project|phase|host",
            'PREP="$(execenv_phase_prepare',
            "execenv_phase_teardown \"$ROOT\"",
            "release:wave-executor` only when",
        ):
            self.assertNotIn(obsolete, source)
            self.assertNotIn(obsolete, generated)
        self.assertTrue((PLUGIN / "bin" / "release-timeout.py").is_file())

    def test_quick_allows_dirty_callers_and_parallel_worktrees(self) -> None:
        source = (REPO_ROOT / "skills" / "quick" / "SKILL.md").read_text()
        generated = (PLUGIN / "skills" / "quick" / "SKILL.md").read_text()
        for contract in (
            "A dirty caller checkout is allowed.",
            "quick/<timestamp>-<slug>",
            "release-worktrees/quick/<timestamp>-<slug>",
            "multiple quick tasks can run in parallel",
            "never switch the caller checkout",
            "call `land_branch` for the quick branch/worktree",
            "RESULT=held-dirty",
        ):
            self.assertIn(contract, source)
            self.assertIn(contract, generated)
        for obsolete in (
            "Otherwise require a clean tree",
            "Never create a sibling worktree",
            "land the in-place branch",
        ):
            self.assertNotIn(obsolete, source)
            self.assertNotIn(obsolete, generated)

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

    def test_common_development_flow_enforces_clean_code_contract(self) -> None:
        source_agent = (REPO_ROOT / "agents" / "tdd-executor.md").read_text()
        generated_agent = tomllib.loads(
            (PLUGIN / "agents" / "release-tdd-executor.toml").read_text()
        )["developer_instructions"]
        for contract in (
            "intention-revealing names",
            "single-purpose",
            "zero to two arguments",
            "cyclomatic complexity",
            "guard clauses",
            "duplicated knowledge",
            "massive class",
            "primitive obsession",
            "polymorphism",
            "characterization test",
            "Preserve public",
            "every logical baby step must return to green",
        ):
            self.assertIn(contract, source_agent)
            self.assertIn(contract, generated_agent)

        for skill_name in ("execute", "quick", "loop"):
            source = (REPO_ROOT / "skills" / skill_name / "SKILL.md").read_text()
            generated = (PLUGIN / "skills" / skill_name / "SKILL.md").read_text()
            for contract in (
                "Common implementation quality — mandatory",
                "meaningful names",
                "guard clauses",
                "baby steps",
                "preserve public signatures",
            ):
                self.assertIn(contract, source)
                self.assertIn(contract, generated)

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
            retired = target / "release-django-discuss-orchestrator.toml"
            retired.write_text('name = "release-django-discuss-orchestrator"\n')
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
            self.assertEqual(json.loads(first.stdout)["removed"], [retired.name])
            self.assertEqual(json.loads(second.stdout)["updated"], 0)
            self.assertEqual(json.loads(second.stdout)["removed"], [])
            self.assertEqual(sentinel.read_text(), 'name = "unrelated"\n')
            self.assertFalse(retired.exists())

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

    def test_efficiency_policy_is_global_compact_and_rtk_aware(self) -> None:
        policy_path = REPO_ROOT / "hooks" / "release-efficiency-policy.md"
        hook_path = REPO_ROOT / "hooks" / "release-efficiency-context.js"
        policy = policy_path.read_text()
        self.assertIn("smallest complete change", policy)
        self.assertIn("When RTK is available", policy)
        self.assertIn("Never trade away correctness", policy)
        self.assertNotIn("Headroom", policy)

        claude_hooks = json.loads(
            (REPO_ROOT / ".claude-plugin" / "plugin.json").read_text()
        )["hooks"]
        codex_hooks = json.loads((PLUGIN / "hooks" / "hooks.json").read_text())["hooks"]
        for hooks in (claude_hooks, codex_hooks):
            self.assertIn("SessionStart", hooks)
            self.assertIn("SubagentStart", hooks)
            serialized = json.dumps(hooks)
            self.assertEqual(serialized.count("release-efficiency-context.js"), 2)

        generated_policy = PLUGIN / "hooks" / policy_path.name
        generated_hook = PLUGIN / "hooks" / hook_path.name
        self.assertEqual(generated_policy.read_text(), policy)
        self.assertTrue(generated_hook.is_file())

        if not shutil.which("node"):
            self.skipTest("node unavailable")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            environment = os.environ.copy()
            environment.pop("PLUGIN_DATA", None)
            environment["PATH"] = str(root)
            command = [shutil.which("node"), str(hook_path)]

            session = subprocess.run(
                [*command, "SessionStart"], capture_output=True, text=True,
                check=True, env=environment,
            )
            self.assertIn("release_efficiency_contract", session.stdout)
            self.assertNotIn("RTK detected", session.stdout)

            subagent = subprocess.run(
                [*command, "SubagentStart"], capture_output=True, text=True,
                check=True, env=environment,
            )
            output = json.loads(subagent.stdout)
            self.assertEqual(
                output["hookSpecificOutput"]["hookEventName"], "SubagentStart"
            )

            rtk_name = "rtk.EXE" if os.name == "nt" else "rtk"
            rtk = root / rtk_name
            rtk.write_text("")
            rtk.chmod(0o755)
            detected = subprocess.run(
                [*command, "SessionStart"], capture_output=True, text=True,
                check=True, env=environment,
            )
            self.assertIn("RTK detected on PATH", detected.stdout)

            environment["PLUGIN_DATA"] = str(root / "plugin-data")
            codex = subprocess.run(
                [*command, "SessionStart"], capture_output=True, text=True,
                check=True, env=environment,
            )
            output = json.loads(codex.stdout)
            self.assertEqual(output["systemMessage"], "RELEASE_EFFICIENCY_ACTIVE")
            self.assertEqual(
                output["hookSpecificOutput"]["hookEventName"], "SessionStart"
            )

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

    def test_token_collector_emits_codex_cumulative_deltas(self) -> None:
        if not shutil.which("node"):
            self.skipTest("node unavailable")
        received: list[dict] = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                body = self.rfile.read(int(self.headers["Content-Length"]))
                received.append(json.loads(body))
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"ok":true}')

            def log_message(self, _format: str, *args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                transcript = root / "rollout.jsonl"
                transcript.write_text(
                    json.dumps({
                        "type": "turn_context", "payload": {"model": "gpt-5.6-sol"},
                    }) + "\n" +
                    json.dumps({
                        "type": "event_msg", "ordinal": 10, "timestamp": "2026-01-01T00:00:00Z",
                        "payload": {"type": "token_count", "info": {"total_token_usage": {
                            "input_tokens": 100, "cached_input_tokens": 40,
                            "cache_write_input_tokens": 10, "output_tokens": 20,
                        }}},
                    }) + "\n" +
                    json.dumps({
                        "type": "event_msg", "ordinal": 20, "timestamp": "2026-01-01T00:00:01Z",
                        "payload": {"type": "token_count", "info": {"total_token_usage": {
                            "input_tokens": 160, "cached_input_tokens": 70,
                            "cache_write_input_tokens": 10, "output_tokens": 27,
                        }}},
                    }) + "\n"
                )
                environment = os.environ.copy()
                environment["PLUGIN_DATA"] = str(root / "plugin-data")
                environment["RELEASE_TOKEN_PORT"] = str(server.server_port)
                payload = {"session_id": "codex-test", "transcript_path": str(transcript), "cwd": str(root)}
                command = ["node", str(PLUGIN / "hooks" / "release-token-collector.js")]
                subprocess.run(command, input=json.dumps(payload), text=True, check=True, env=environment)

                self.assertEqual(
                    [(event["input"], event["output"], event["cache_read"], event["cache_create"])
                     for event in received],
                    [(50, 20, 40, 10), (30, 7, 30, 0)],
                )
                self.assertTrue(all(event["model"] == "gpt-5.6-sol" for event in received))
                cursor = json.loads((
                    root / "plugin-data" / "token-tracker" / "cursors" / "codex-test.json"
                ).read_text())
                self.assertEqual(cursor["codex_totals"]["input_tokens"], 160)

                subprocess.run(command, input=json.dumps(payload), text=True, check=True, env=environment)
                self.assertEqual(len(received), 2)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

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
