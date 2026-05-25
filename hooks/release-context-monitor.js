#!/usr/bin/env node
// release-sdk-hook-version: 0.2.0
// release-context-monitor.js — PostToolUse hook (advisory)
//
// Tracks tool-call count per session to warn when context budget is getting
// tight. Fires threshold-based advisories so Claude can proactively summarize
// or hand off via /release:pause-work before auto-compaction kicks in.
//
// Advisory only — never blocks. Disable via env: RELEASE_SDK_CONTEXT_MONITOR=0.

const fs = require('fs');
const path = require('path');

if (process.env.RELEASE_SDK_CONTEXT_MONITOR === '0') {
  process.exit(0);
}

const THRESHOLDS = [
  {
    at: 50,
    message:
      'Context usage moderate — consider summarizing intermediate findings.',
  },
  {
    at: 100,
    message:
      'Context usage high — consider `/release:pause-work` or wrap-up of current phase before continuing.',
  },
  {
    at: 150,
    message:
      'Context usage critical — auto-compaction likely soon. Commit progress and capture handoff notes via `/release:pause-work`.',
  },
];

function resolveCacheDir() {
  const repoRoot = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const primary = path.join(repoRoot, '.claude-plugin-cache');
  try {
    fs.mkdirSync(primary, { recursive: true });
    // Verify writability with a probe file
    const probe = path.join(primary, '.write-probe');
    fs.writeFileSync(probe, '');
    fs.unlinkSync(probe);
    return primary;
  } catch {
    const fallback = path.join('/tmp', 'release-sdk-context-monitor');
    try {
      fs.mkdirSync(fallback, { recursive: true });
    } catch {}
    return fallback;
  }
}

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => (input += chunk));
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const sessionId = data.session_id || 'unknown';

    const cacheDir = resolveCacheDir();
    const stateFile = path.join(
      cacheDir,
      `release-context-monitor-${sessionId}.json`
    );

    let state = {
      tool_calls_count: 0,
      last_warning_threshold: 0,
      session_start_iso: new Date().toISOString(),
    };

    if (fs.existsSync(stateFile)) {
      try {
        const raw = fs.readFileSync(stateFile, 'utf8');
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object') {
          state = {
            tool_calls_count:
              typeof parsed.tool_calls_count === 'number'
                ? parsed.tool_calls_count
                : 0,
            last_warning_threshold:
              typeof parsed.last_warning_threshold === 'number'
                ? parsed.last_warning_threshold
                : 0,
            session_start_iso:
              typeof parsed.session_start_iso === 'string'
                ? parsed.session_start_iso
                : new Date().toISOString(),
          };
        }
      } catch {
        // Corrupt state — start fresh
      }
    }

    state.tool_calls_count += 1;

    // Determine highest threshold crossed that hasn't been warned yet
    let triggered = null;
    for (const t of THRESHOLDS) {
      if (
        state.tool_calls_count >= t.at &&
        state.last_warning_threshold < t.at
      ) {
        triggered = t;
      }
    }

    if (triggered) {
      state.last_warning_threshold = triggered.at;
    }

    try {
      fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
    } catch {
      // Persist failure is non-fatal
    }

    if (triggered) {
      const output = {
        continue: true,
        additionalContext: `[release-sdk context-monitor @ ${state.tool_calls_count} tool calls] ${triggered.message}`,
      };
      process.stdout.write(JSON.stringify(output));
    }

    process.exit(0);
  } catch {
    process.exit(0);
  }
});
