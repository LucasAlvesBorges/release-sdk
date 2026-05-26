#!/usr/bin/env node
// release-sdk-hook-version: 0.1.0
// release-token-collector.js — PostToolUse hook
// Parses transcript tail for new assistant message usage, POSTs to worker on :47777.
// Fails silent: never blocks parent tool, never errors.

const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');

const PORT = parseInt(process.env.RELEASE_TOKEN_PORT || '47777', 10);
const HOST = '127.0.0.1';
const STATE_DIR = path.join(os.homedir(), '.claude', 'token-tracker', 'cursors');
const TAIL_BYTES = 256 * 1024;

function readStdin() {
  return new Promise(resolve => {
    let d = '';
    const t = setTimeout(() => resolve(d), 1500);
    process.stdin.on('data', c => d += c);
    process.stdin.on('end', () => { clearTimeout(t); resolve(d); });
  });
}

function readTail(filePath, bytes) {
  const stat = fs.statSync(filePath);
  const start = Math.max(0, stat.size - bytes);
  const fd = fs.openSync(filePath, 'r');
  const buf = Buffer.alloc(stat.size - start);
  fs.readSync(fd, buf, 0, buf.length, start);
  fs.closeSync(fd);
  return buf.toString('utf8');
}

function parseLines(txt) {
  const out = [];
  let firstSkipped = false;
  for (const line of txt.split('\n')) {
    if (!line.trim()) continue;
    if (!firstSkipped) { firstSkipped = true; continue; } // partial first line
    try { out.push(JSON.parse(line)); } catch {}
  }
  return out;
}

function loadCursor(sessionId) {
  const f = path.join(STATE_DIR, `${sessionId}.json`);
  if (!fs.existsSync(f)) return { last_uuid: null };
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return { last_uuid: null }; }
}

function saveCursor(sessionId, cursor) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(path.join(STATE_DIR, `${sessionId}.json`), JSON.stringify(cursor));
}

function postEvent(ev) {
  return new Promise(resolve => {
    const body = JSON.stringify(ev);
    const req = http.request({
      host: HOST, port: PORT, path: '/event', method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      timeout: 800
    }, res => { res.on('data', () => {}); res.on('end', () => resolve(true)); });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.write(body);
    req.end();
  });
}

function extractSkill(entries) {
  // Walk backwards through user messages looking for skill signals.
  // Plugin slash commands inject content like:
  //   "Base directory for this skill: .../skills/<name>\n# /release:<name>"
  // Built-in commands inject: "<command-name>/clear</command-name>"
  for (let i = entries.length - 1; i >= 0; i--) {
    const e = entries[i];
    if (e.type !== 'user') continue;
    if (e.isMeta) continue;
    const content = JSON.stringify(e.message?.content || '');

    // Plugin slash commands — path-based (most reliable for /release:*)
    let m = content.match(/Base directory for this skill:[^"\\n]*?\/skills\/([a-z][a-z0-9_-]+)/i);
    if (m) return `release:${m[1]}`;

    // Plugin slash commands — header `# /release:<name>` or `# /<name>`
    m = content.match(/#\s+\/(release:[a-z0-9_-]+|[a-z][a-z0-9_-]+)/);
    if (m) return m[1];

    // Built-in slash commands — <command-name>/clear</command-name>
    m = content.match(/<command-name>\/?([a-z][a-z0-9:_-]*)<\/command-name>/i);
    if (m) return m[1];

    // Pure text user message (not slash command) → keep walking back, don't break.
  }
  return null;
}

async function main() {
  const stdin = await readStdin();
  let data;
  try { data = JSON.parse(stdin); } catch { return; }

  const transcriptPath = data.transcript_path;
  const sessionId = data.session_id;
  const cwd = data.cwd || process.cwd();
  if (!transcriptPath || !sessionId) return;
  if (!fs.existsSync(transcriptPath)) return;

  const txt = readTail(transcriptPath, TAIL_BYTES);
  const entries = parseLines(txt);
  if (entries.length === 0) return;

  const skill = extractSkill(entries);
  const cursor = loadCursor(sessionId);
  let newLast = cursor.last_uuid;
  let started = cursor.last_uuid == null;

  const toPost = [];
  for (const e of entries) {
    if (!started) {
      if (e.uuid === cursor.last_uuid) started = true;
      continue;
    }
    if (e.type !== 'assistant') continue;
    const u = e.message?.usage;
    if (!u) continue;
    if (!u.input_tokens && !u.output_tokens && !u.cache_read_input_tokens && !u.cache_creation_input_tokens) continue;

    toPost.push({
      ts: e.timestamp ? Math.floor(new Date(e.timestamp).getTime() / 1000) : Math.floor(Date.now() / 1000),
      session_id: sessionId,
      uuid: e.uuid,
      model: e.message?.model || data.model || 'unknown',
      input: u.input_tokens || 0,
      output: u.output_tokens || 0,
      cache_read: u.cache_read_input_tokens || 0,
      cache_create: u.cache_creation_input_tokens || 0,
      cwd,
      skill
    });
    newLast = e.uuid;
  }

  for (const ev of toPost) await postEvent(ev);
  if (newLast && newLast !== cursor.last_uuid) saveCursor(sessionId, { last_uuid: newLast });
}

main().catch(() => {});
