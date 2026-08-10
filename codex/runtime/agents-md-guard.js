#!/usr/bin/env node
'use strict';

// release-agents-md-guard.js — PreToolUse hook (blocking): enforces the
// release-sdk Codex token-economy policy's mandatory-AGENTS.md rule (§4.1).
// Codex-only — no Claude Code equivalent, ported nowhere else.
//
// Blocks Edit/Write/apply_patch with exit(2) + {"decision":"block",...} when
// the target project's root AGENTS.md is missing, following the one existing
// blocking precedent in this repo (hooks/django-validate-commit.sh). Every
// other Edit/Write guard in this codebase is advisory-only; this one is not.
//
// OPT-OUT: set RELEASE_SDK_DISABLE_AGENTS_MD_GUARD=1 to skip.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

if (process.env.RELEASE_SDK_DISABLE_AGENTS_MD_GUARD === '1') {
  process.exit(0);
}

function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    const timer = setTimeout(() => resolve(data), 3000);
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => {
      clearTimeout(timer);
      resolve(data);
    });
  });
}

function patchTargetPaths(command) {
  const header = /^\*\*\* (?:Add|Update|Delete) File: (.+)$/gm;
  return [...command.matchAll(header)].map((match) => match[1].trim());
}

function realpathOf(candidate) {
  try {
    return fs.realpathSync(candidate);
  } catch {
    return candidate;
  }
}

// A tool payload's file_path is often already absolute, so realpath'ing cwd
// alone doesn't help (path.resolve ignores the base when fp is absolute).
// Resolve the target, then realpath its (existing) directory and reattach
// the basename — the file itself may not exist yet, but its directory does.
function toRealTarget(resolved) {
  const dir = realpathOf(path.dirname(resolved));
  return path.join(dir, path.basename(resolved));
}

function resolveTargetPaths(payload) {
  const toolName = payload.tool_name;
  const cwd = realpathOf(payload.cwd || process.cwd());
  if (toolName === 'apply_patch') {
    const command = payload.tool_input?.command || '';
    return patchTargetPaths(command).map((p) => toRealTarget(path.resolve(cwd, p)));
  }
  if (toolName === 'Edit' || toolName === 'Write') {
    const fp = payload.tool_input?.file_path || payload.tool_input?.path;
    return fp ? [toRealTarget(path.resolve(cwd, fp))] : [];
  }
  return [];
}

function findProjectRoot(startDir) {
  const result = spawnSync('git', ['-C', startDir, 'rev-parse', '--show-toplevel'], {
    encoding: 'utf8',
    timeout: 2000,
  });
  if (!result.error && result.status === 0 && result.stdout.trim()) {
    return result.stdout.trim();
  }
  return startDir;
}

function findExistingAgentsMd(root) {
  let entries;
  try {
    entries = fs.readdirSync(root);
  } catch {
    return null;
  }
  const match = entries.find((name) => name.toLowerCase() === 'agents.md');
  return match ? path.join(root, match) : null;
}

function readAgentsMdMode(root) {
  const configPath = path.join(root, '.codex', 'config.toml');
  let text;
  try {
    text = fs.readFileSync(configPath, 'utf8');
  } catch {
    return 'strict';
  }
  const sectionStart = text.indexOf('[agents_md]');
  if (sectionStart < 0) return 'strict';
  const sectionEnd = text.indexOf('\n[', sectionStart + 1);
  const section = text.slice(sectionStart, sectionEnd < 0 ? undefined : sectionEnd);
  const match = section.match(/^\s*mode\s*=\s*"([^"]+)"/m);
  return match && (match[1] === 'strict' || match[1] === 'bootstrap') ? match[1] : 'strict';
}

function block(code, reason) {
  process.stdout.write(JSON.stringify({ decision: 'block', code, reason }));
  process.exit(2);
}

async function main() {
  const raw = await readStdin();
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return; // malformed payload — fail open
  }

  if (!['Edit', 'Write', 'apply_patch'].includes(payload.tool_name)) return;

  const targets = resolveTargetPaths(payload);
  if (targets.length === 0) return; // couldn't resolve a path — fail open

  const startDir = path.dirname(targets[0]);
  const root = findProjectRoot(startDir);
  const existing = findExistingAgentsMd(root);
  if (existing) return; // gate satisfied

  const rootAgentsMd = path.join(root, 'AGENTS.md');
  const creatingAgentsMd = targets.some((t) => t.toLowerCase() === rootAgentsMd.toLowerCase());
  if (creatingAgentsMd) return; // always allow creating the file itself

  const mode = readAgentsMdMode(root);
  if (mode === 'bootstrap') {
    block(
      'AGENTS_MD_REQUIRED',
      `No AGENTS.md at project root (${root}). Bootstrap mode: spawn release-agents-md-builder ` +
        'read-only (it may write ONLY AGENTS.md), let it draft and save the file, then re-run this task.'
    );
  } else {
    block(
      'AGENTS_MD_REQUIRED',
      `No AGENTS.md at project root (${root}). Strict mode: writes are blocked until it exists. ` +
        'Create one (see codex/contracts/roles/agents-md-builder.md for required sections) or switch ' +
        '[agents_md].mode to "bootstrap" in .codex/config.toml, then re-run.'
    );
  }
}

main().catch(() => {});
