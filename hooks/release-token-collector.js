#!/usr/bin/env node
// release-sdk-hook-version: 0.2.0
// release-token-collector.js — PostToolUse hook
// Parses only the new transcript bytes for Claude or Codex usage, POSTs to worker on :47777.
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

function readTranscriptChunk(filePath, byteOffset, fallbackBytes) {
  const stat = fs.statSync(filePath);
  const incremental = Number.isInteger(byteOffset) && byteOffset >= 0 && byteOffset <= stat.size;
  let start = incremental ? byteOffset : Math.max(0, stat.size - fallbackBytes);
  const fd = fs.openSync(filePath, 'r');
  const buf = Buffer.alloc(stat.size - start);
  fs.readSync(fd, buf, 0, buf.length, start);
  fs.closeSync(fd);

  // A fallback tail can begin inside a JSONL record. Incremental reads always
  // begin at a newline boundary saved by the previous invocation.
  let complete = buf;
  if (!incremental && start > 0) {
    const firstNewline = buf.indexOf(0x0a);
    if (firstNewline < 0) return { text: '', nextOffset: start };
    start += firstNewline + 1;
    complete = buf.subarray(firstNewline + 1);
  }

  const lastNewline = complete.lastIndexOf(0x0a);
  if (lastNewline < 0) return { text: '', nextOffset: start };
  return {
    text: complete.subarray(0, lastNewline + 1).toString('utf8'),
    nextOffset: start + lastNewline + 1,
  };
}

function parseLines(txt) {
  const out = [];
  for (const line of txt.split('\n')) {
    if (!line.trim()) continue;
    try { out.push(JSON.parse(line)); } catch {}
  }
  return out;
}

function loadCursor(sessionId) {
  const f = path.join(STATE_DIR, `${sessionId}.json`);
  if (!fs.existsSync(f)) return { last_uuid: null, byte_offset: null, skill: null, codex_totals: null };
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); }
  catch { return { last_uuid: null, byte_offset: null, skill: null, codex_totals: null }; }
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

function entryText(entry) {
  try {
    return JSON.stringify(
      entry.message?.content || entry.payload?.item?.content || entry.payload?.message?.content || ''
    );
  } catch { return ''; }
}

function skillFromEntry(entry) {
  if (entry.attributionSkill) return entry.attributionSkill;
  const isCodexUser = entry.type === 'event_msg' && entry.payload?.type === 'item_completed' &&
    entry.payload?.item?.type === 'UserMessage';
  if ((entry.type !== 'user' && !isCodexUser) || entry.isMeta) return null;
  const content = entryText(entry);
  let match = content.match(/Base directory for this skill:[^"\\n]*?\/skills\/([a-z][a-z0-9_-]+)/i);
  if (match) return `release:${match[1]}`;
  match = content.match(/#\s+\/(release:[a-z0-9_-]+|[a-z][a-z0-9_-]+)/);
  if (match) return match[1];
  match = content.match(/<command-name>\/?([a-z][a-z0-9:_-]*)<\/command-name>/i);
  return match ? match[1] : null;
}

function updateContext(context, entry) {
  const skill = skillFromEntry(entry);
  if (skill) context.skill = skill;
  if (entry.attributionAgent) context.agent = entry.attributionAgent;
  const runtimeModel = entry.type === 'turn_context'
    ? entry.payload?.model
    : entry.payload?.thread_settings?.model;
  if (runtimeModel) context.model = runtimeModel;

  const content = entryText(entry);
  const phase = content.match(/\.release-planning\/phases\/(\d{1,3})-/i) ||
    content.match(/<command-args>\s*(\d{1,3})\b/i) ||
    content.match(/\bphase(?:_number)?["'\s:=_-]+0*(\d{1,3})\b/i);
  if (phase) context.phase = phase[1].padStart(2, '0');
  const complexity = content.match(/\bC([0-4])\b/i);
  if (complexity) context.complexity = `C${complexity[1]}`;

  if (/--strict\b/.test(content)) context.mode = 'strict';
  else if (/--loop\b/.test(content) || context.skill === 'release:loop') context.mode = 'loop';
  else if (context.agent) context.mode = 'agent';
  else if (context.skill === 'release:quick' || context.skill === 'release:fast') context.mode = 'bounded';
  else if (context.skill?.startsWith('release:')) context.mode = 'workflow';
  else context.mode = context.mode || 'interactive';
}

function codexTotalUsage(entry) {
  if (entry.type !== 'event_msg' || entry.payload?.type !== 'token_count') return null;
  return entry.payload?.info?.total_token_usage || null;
}

function normalizedCodexTotals(usage) {
  const number = key => Number.isFinite(Number(usage?.[key])) ? Math.max(0, Number(usage[key])) : 0;
  return {
    input_tokens: number('input_tokens'),
    output_tokens: number('output_tokens'),
    cached_input_tokens: number('cached_input_tokens'),
    cache_write_input_tokens: number('cache_write_input_tokens'),
  };
}

function codexUsageDelta(usage, previous) {
  const current = normalizedCodexTotals(usage);
  const prior = previous ? normalizedCodexTotals(previous) : normalizedCodexTotals(null);
  const reset = Object.keys(current).some(key => current[key] < prior[key]);
  const baseline = reset ? normalizedCodexTotals(null) : prior;
  const delta = Object.fromEntries(Object.keys(current).map(key => [key, current[key] - baseline[key]]));
  const cacheRead = delta.cached_input_tokens;
  const cacheCreate = delta.cache_write_input_tokens;
  return {
    totals: current,
    input: Math.max(0, delta.input_tokens - cacheRead - cacheCreate),
    output: delta.output_tokens,
    cache_read: cacheRead,
    cache_create: cacheCreate,
  };
}

function toolMetrics(entry) {
  let spawns = 0;
  let gateRuns = 0;
  const blocks = Array.isArray(entry.message?.content) ? entry.message.content : [];
  for (const block of blocks) {
    if (block.type !== 'tool_use') continue;
    const name = String(block.name || '').toLowerCase();
    if (name === 'agent' || name.endsWith('spawn_agent') || name === 'task') spawns += 1;
    const command = String(block.input?.command || block.input?.cmd || '');
    if (/\b(run_gate_cached|run_gate|run_quick_gate)\b/.test(command)) gateRuns += 1;
  }
  return { spawns, gate_runs: gateRuns };
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

  const transcriptName = path.basename(transcriptPath, path.extname(transcriptPath));
  const cursorId = transcriptName.startsWith('agent-') ? `${sessionId}-${transcriptName}` : sessionId;
  const cursor = loadCursor(cursorId);
  const stat = fs.statSync(transcriptPath);
  if (Number.isInteger(cursor.byte_offset) && cursor.byte_offset > stat.size) {
    cursor.byte_offset = null;
    cursor.last_uuid = null;
  }
  const chunk = readTranscriptChunk(transcriptPath, cursor.byte_offset, TAIL_BYTES);
  const entries = parseLines(chunk.text);
  const incremental = Number.isInteger(cursor.byte_offset);
  let newLast = cursor.last_uuid;
  let started = incremental || cursor.last_uuid == null;
  const context = {
    skill: cursor.skill || null,
    agent: cursor.agent || null,
    phase: cursor.phase || null,
    complexity: cursor.complexity || null,
    mode: cursor.mode || null,
    model: cursor.model || data.model || null,
  };
  let codexTotals = cursor.codex_totals || null;
  const entriesByUuid = new Map(entries.filter(e => e.uuid).map(e => [e.uuid, e]));

  const toPost = [];
  for (const e of entries) {
    if (!started) {
      if (e.uuid === cursor.last_uuid) started = true;
      continue;
    }
    updateContext(context, e);
    const codexUsage = codexTotalUsage(e);
    const claudeUsage = e.type === 'assistant' ? e.message?.usage : null;
    if (!codexUsage && !claudeUsage) continue;

    let usage;
    if (codexUsage) {
      usage = codexUsageDelta(codexUsage, codexTotals);
      codexTotals = usage.totals;
    } else {
      usage = {
        input: claudeUsage.input_tokens || 0,
        output: claudeUsage.output_tokens || 0,
        cache_read: claudeUsage.cache_read_input_tokens || 0,
        cache_create: claudeUsage.cache_creation_input_tokens || 0,
      };
    }
    if (!usage.input && !usage.output && !usage.cache_read && !usage.cache_create) continue;

    const eventMs = e.timestamp ? new Date(e.timestamp).getTime() : Date.now();
    const parentMs = entriesByUuid.get(e.parentUuid)?.timestamp
      ? new Date(entriesByUuid.get(e.parentUuid).timestamp).getTime()
      : null;
    const latencyMs = parentMs != null && eventMs >= parentMs && eventMs - parentMs <= 60 * 60 * 1000
      ? eventMs - parentMs
      : 0;
    const metrics = toolMetrics(e);
    const agent = e.attributionAgent || context.agent || null;
    const skill = e.attributionSkill || context.skill || null;

    toPost.push({
      ts: Math.floor(eventMs / 1000),
      session_id: sessionId,
      uuid: e.uuid || (e.ordinal != null ? `codex-${e.ordinal}` : `codex-${e.timestamp || eventMs}`),
      workflow: agent ? `${skill || 'interactive'}>${agent}` : (skill || 'interactive'),
      skill,
      agent,
      agent_id: e.agentId || null,
      phase: context.phase,
      complexity: context.complexity,
      mode: agent ? 'agent' : (context.mode || 'interactive'),
      latency_ms: Math.round(latencyMs),
      spawns: metrics.spawns,
      gate_runs: metrics.gate_runs,
      model: e.message?.model || context.model || data.model || 'unknown',
      input: usage.input,
      output: usage.output,
      cache_read: usage.cache_read,
      cache_create: usage.cache_create,
      cwd,
    });
    newLast = e.uuid || newLast;
  }

  for (const ev of toPost) await postEvent(ev);
  if (chunk.nextOffset !== cursor.byte_offset || newLast !== cursor.last_uuid ||
      context.skill !== cursor.skill || context.agent !== cursor.agent ||
      context.phase !== cursor.phase || context.complexity !== cursor.complexity || context.mode !== cursor.mode) {
    saveCursor(cursorId, {
      last_uuid: newLast,
      byte_offset: chunk.nextOffset,
      skill: context.skill,
      agent: context.agent,
      phase: context.phase,
      complexity: context.complexity,
      mode: context.mode,
      model: context.model,
      codex_totals: codexTotals,
    });
  }
}

main().catch(() => {});
