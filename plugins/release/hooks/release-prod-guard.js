#!/usr/bin/env node
// release-sdk-hook-version: 0.1.0
// release-prod-guard.js — PreToolUse(Bash) guard against touching production from inside an
// SDK unit (a running /release:execute phase or /release:quick task).
//
// WHY: a phase executor once "fixed" a failing test by changing database roles on the production
// host over ssh. Nothing stopped it because nothing knew the command was aimed at prod. This hook
// does one thing: when a Bash command looks like it reaches a remote/production surface AND an SDK
// unit is active, it BLOCKS unless the user explicitly allowed prod for that unit. Outside a unit
// (a freeform session debugging prod on purpose) it only WARNS.
//
// Active unit = any of:
//   - cwd is under a `release-worktrees/` directory (quick / phase worktree)
//   - `.release-planning/.unit-active` exists and is younger than 12 h (execute/quick write it)
//   - a `.release-planning/phases/*/.progress.json` was updated in the last 2 h
// Allowed = any of:
//   - env RELEASE_ALLOW_PROD=1
//   - `.release-planning/.allow-prod` exists (skills create it for `--allow-prod`, land removes it)
//   - the command carries the literal marker `#allow-prod`
//   - the command matches an `allow:` regex from `.release-planning/PROD-GUARD.yml`
// Config `.release-planning/PROD-GUARD.yml` (all optional, one `key: value` per line):
//   mode: block | warn | off      (default block)
//   pattern: <regex>              (added to the built-in list; repeatable)
//   allow: <regex>                (repeatable)
// Fails open: any parse/IO error → exit 0 silently. Never blocks git push (the land contract owns it).

const fs = require('fs');
const path = require('path');

const BUILTIN = [
  ['SSH', /(^|[\s;&|(`])ssh\s+(?:-\w+(?:\s+\S+)?\s+)*(?:\S+@)?[\w.-]+/i],
  ['SCP', /(^|[\s;&|(`])scp\s+/i],
  ['RSYNC_REMOTE', /(^|[\s;&|(`])rsync\s[^|]*\S+:\S/i],
  ['PSQL_REMOTE', /\bpsql\b[^|]*(?:\s-h\s|\s--host[= ]|postgres(?:ql)?:\/\/)/i],
  ['DOKPLOY', /\bdokploy\b/i],
  ['KUBECTL', /\bkubectl\b/i],
  ['DOCKER_REMOTE', /\bdocker\s+(?:-H\s|--host[= ]|context\s+use)/i],
  ['PROD_ENV', /(?:--env(?:ironment)?[= ]|\bENV=|\bDJANGO_ENV=|\bNODE_ENV=|\bAPP_ENV=)prod/i],
  ['PROD_SETTINGS', /DJANGO_SETTINGS_MODULE=\S*prod/i],
  ['PAAS', /\b(?:heroku|flyctl|fly)\s+(?:ssh|run|deploy|pg:psql|postgres)/i],
  ['GH_WORKFLOW_RUN', /\bgh\s+workflow\s+run\b/i],
  ['EAS_SUBMIT', /\beas\s+(?:submit|build\b[^|]*--auto-submit)/i],
];

function safeRead(file) {
  try { return fs.readFileSync(file, 'utf8'); } catch { return ''; }
}

function ageMs(file) {
  try { return Date.now() - fs.statSync(file).mtimeMs; } catch { return Infinity; }
}

function findProjectRoot(start) {
  let dir = start;
  for (let i = 0; i < 12 && dir; i++) {
    if (fs.existsSync(path.join(dir, '.release-planning')) || fs.existsSync(path.join(dir, '.git'))) return dir;
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  return start;
}

function loadConfig(root) {
  const cfg = { mode: 'block', patterns: [], allows: [] };
  const text = safeRead(path.join(root, '.release-planning', 'PROD-GUARD.yml'));
  for (const raw of text.split('\n')) {
    const line = raw.replace(/#.*$/, '').trim();
    const m = line.match(/^-?\s*(mode|pattern|allow)\s*:\s*(.+)$/);
    if (!m) continue;
    const value = m[2].trim().replace(/^['"`]|['"`]$/g, '');
    if (m[1] === 'mode') { if (['block', 'warn', 'off'].includes(value)) cfg.mode = value; continue; }
    try { (m[1] === 'pattern' ? cfg.patterns : cfg.allows).push(new RegExp(value, 'i')); } catch {}
  }
  return cfg;
}

function unitActive(cwd, root) {
  if (process.env.RELEASE_UNIT_ACTIVE === '1') return 'env';
  if (/(^|\/)release-worktrees\//.test(cwd + '/')) return 'worktree';
  if (ageMs(path.join(root, '.release-planning', '.unit-active')) < 12 * 3600e3) return 'unit-active';
  const phases = path.join(root, '.release-planning', 'phases');
  try {
    for (const name of fs.readdirSync(phases)) {
      if (ageMs(path.join(phases, name, '.progress.json')) < 2 * 3600e3) return `progress:${name}`;
    }
  } catch {}
  return '';
}

function allowed(command, root, cfg) {
  if (process.env.RELEASE_ALLOW_PROD === '1') return 'env';
  if (/#\s*allow-prod\b/.test(command)) return 'marker';
  if (fs.existsSync(path.join(root, '.release-planning', '.allow-prod'))) return '.allow-prod';
  if (cfg.allows.some((re) => re.test(command))) return 'config';
  return '';
}

function inspect(data) {
  if (data.tool_name !== 'Bash') return null;
  const command = String((data.tool_input || {}).command || '');
  if (!command) return null;
  const cwd = data.cwd || process.cwd();
  const root = findProjectRoot(cwd);
  const cfg = loadConfig(root);
  if (cfg.mode === 'off') return null;

  const hit = BUILTIN.find(([, re]) => re.test(command)) ||
    (cfg.patterns.find((re) => re.test(command)) ? ['PROJECT_PATTERN'] : null);
  if (!hit) return null;

  const why = allowed(command, root, cfg);
  if (why) return null;
  const unit = unitActive(cwd, root);
  const reason = `PROD GUARD (${hit[0]}): this command looks like it reaches a remote/production surface.`;
  if (unit && cfg.mode === 'block') {
    return {
      block: true,
      reason: `${reason} An SDK unit is active (${unit}); executors never touch prod. ` +
        'If the user explicitly wants this, re-run the skill with --allow-prod, ' +
        'or append `#allow-prod` to the command, or set RELEASE_ALLOW_PROD=1.',
    };
  }
  return { block: false, reason: `${reason} Not blocked (no active SDK unit). Prefer dev data; confirm intent before mutating prod.` };
}

let input = '';
const timeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  clearTimeout(timeout);
  try {
    const verdict = inspect(JSON.parse(input));
    if (!verdict) return;
    if (verdict.block) {
      process.stdout.write(JSON.stringify({ decision: 'block', code: 'PROD_GUARD', reason: verdict.reason }));
      process.exitCode = 2;
      return;
    }
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: `release-sdk advisory:\n- ${verdict.reason}` },
    }));
  } catch {
    process.exitCode = 0;
  }
});
