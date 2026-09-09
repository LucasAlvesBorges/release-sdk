#!/usr/bin/env node
'use strict';

// Inject the release-sdk efficiency policy once per session and once per
// subagent. It is deliberately advisory and never writes runtime state.

const fs = require('fs');
const path = require('path');
const net = require('net');
const { spawn, execFileSync } = require('child_process');

const event = process.argv[2] === 'SubagentStart' ? 'SubagentStart' : 'SessionStart';

// Only when the plugin runtime exports CLAUDE_PLUGIN_ROOT and no PLUGIN_DATA (i.e. not Codex): make
// sure the token worker is listening so PostToolUse events are stored instead of spooled. The
// tracker went dark for two months once because nobody had run /release:tokens after a reboot.
// The worker owns its data directory and log; this hook only spawns it detached.
function ensureTokenWorker() {
  if (event !== 'SessionStart') return;
  if (process.env.RELEASE_TOKEN_AUTOSTART === '0' || !process.env.CLAUDE_PLUGIN_ROOT || process.env.PLUGIN_DATA) return;
  const worker = path.join(process.env.CLAUDE_PLUGIN_ROOT, 'bin', 'release-token-worker.js');
  if (!fs.existsSync(worker)) return;
  const port = parseInt(process.env.RELEASE_TOKEN_PORT || '47777', 10);
  const socket = net.connect({ host: '127.0.0.1', port });
  const giveUp = setTimeout(() => { socket.destroy(); start(); }, 400);
  socket.once('connect', () => { clearTimeout(giveUp); socket.end(); });
  socket.once('error', () => { clearTimeout(giveUp); start(); });
  function start() {
    try {
      const child = spawn(process.execPath, [worker], { detached: true, stdio: 'ignore' });
      child.unref();
    } catch {}
  }
}

// One cheap line when the repo carries leftover SDK units, so `git worktree list` never silently
// grows to 50 entries again. Counts only what /release:gc would prune; never mutates anything.
function gcHint() {
  if (event !== 'SessionStart' || !process.env.CLAUDE_PLUGIN_ROOT || process.env.RELEASE_GC_HINT === '0') return '';
  const lib = path.join(process.env.CLAUDE_PLUGIN_ROOT, 'bin', 'release-gc-lib.sh');
  if (!fs.existsSync(lib)) return '';
  try {
    const count = execFileSync('bash', ['-c', `. "${lib}" && gc_hint_count "$PWD" 2>/dev/null`], {
      cwd: process.cwd(), timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'],
    }).toString().trim();
    const n = parseInt(count, 10);
    return n >= 3 ? `\n<release_gc_hint>${n} merged/stale SDK worktrees, branches or locks can be pruned: run /release:gc (dry run) then /release:gc --apply.</release_gc_hint>` : '';
  } catch { return ''; }
}

function executableOnPath(name) {
  const directories = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const extensions = process.platform === 'win32'
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';')
    : [''];

  return directories.some((directory) => extensions.some((extension) => {
    const candidate = path.join(directory, `${name}${extension}`);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }));
}

function loadContext() {
  try {
    const policy = fs.readFileSync(
      path.join(__dirname, 'release-efficiency-policy.md'),
      'utf8',
    ).trim();
    const runtime = executableOnPath('rtk')
      ? '\n<release_efficiency_runtime>RTK detected on PATH; use it under the safeguards above.</release_efficiency_runtime>'
      : '';
    return `${policy}${runtime}${gcHint()}`;
  } catch {
    return '';
  }
}

ensureTokenWorker();
const context = loadContext();
if (!context) process.exit(0);

if (process.env.PLUGIN_DATA) {
  process.stdout.write(JSON.stringify({
    systemMessage: 'RELEASE_EFFICIENCY_ACTIVE',
    hookSpecificOutput: {
      hookEventName: event,
      additionalContext: context,
    },
  }));
} else if (event === 'SubagentStart') {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: event,
      additionalContext: context,
    },
  }));
} else {
  process.stdout.write(context);
}
