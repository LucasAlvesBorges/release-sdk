#!/usr/bin/env node
// release-sdk token tracker worker
// HTTP daemon on localhost:47777, JSONL storage, no external deps.

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');

const PORT = parseInt(process.env.RELEASE_TOKEN_PORT || '47777', 10);
const HOST = '127.0.0.1';
const DATA_DIR = path.join(os.homedir(), '.claude', 'token-tracker');
const EVENTS_FILE = path.join(DATA_DIR, 'events.jsonl');
const PID_FILE = path.join(DATA_DIR, 'worker.pid');
const RATE_FILE = path.join(DATA_DIR, 'rate.json');
const DASHBOARD_FILE = path.join(__dirname, 'release-token-dashboard.html');
const FX_FALLBACK = parseFloat(process.env.RELEASE_TOKEN_BRL_FALLBACK || '5.50');
const FX_TTL_MS = 60 * 60 * 1000; // 1h cache

// $/Mtok pricing — keep in sync with Anthropic pricing page.
const PRICING = {
  'claude-opus-4-7':       { in: 15, out: 75, cache_read: 1.5,  cache_write: 18.75 },
  'claude-opus-4-7[1m]':   { in: 15, out: 75, cache_read: 1.5,  cache_write: 18.75 },
  'claude-opus-4-6':       { in: 15, out: 75, cache_read: 1.5,  cache_write: 18.75 },
  'claude-sonnet-4-6':     { in: 3,  out: 15, cache_read: 0.3,  cache_write: 3.75 },
  'claude-sonnet-4-5':     { in: 3,  out: 15, cache_read: 0.3,  cache_write: 3.75 },
  'claude-haiku-4-5':      { in: 1,  out: 5,  cache_read: 0.1,  cache_write: 1.25 },
  'claude-haiku-4-5-20251001': { in: 1, out: 5, cache_read: 0.1, cache_write: 1.25 },
  'default':               { in: 3,  out: 15, cache_read: 0.3,  cache_write: 3.75 }
};

// FX rate (USD→BRL) — fetch from AwesomeAPI, cache 1h to disk, fallback to env/hardcoded.
let fxCache = { rate: FX_FALLBACK, fetched_at: 0, source: 'fallback' };

function loadFxCache() {
  if (!fs.existsSync(RATE_FILE)) return;
  try {
    const d = JSON.parse(fs.readFileSync(RATE_FILE, 'utf8'));
    if (d.rate > 0) fxCache = d;
  } catch {}
}

function saveFxCache() {
  try { fs.writeFileSync(RATE_FILE, JSON.stringify(fxCache)); } catch {}
}

function fetchFxRate() {
  return new Promise(resolve => {
    const req = https.get('https://economia.awesomeapi.com.br/last/USD-BRL', { timeout: 3000 }, res => {
      let body = '';
      res.on('data', c => body += c);
      res.on('end', () => {
        try {
          const j = JSON.parse(body);
          const rate = parseFloat(j.USDBRL?.bid);
          if (rate > 0 && rate < 100) {
            fxCache = { rate, fetched_at: Date.now(), source: 'awesomeapi' };
            saveFxCache();
            return resolve(rate);
          }
          resolve(fxCache.rate);
        } catch { resolve(fxCache.rate); }
      });
    });
    req.on('error', () => resolve(fxCache.rate));
    req.on('timeout', () => { req.destroy(); resolve(fxCache.rate); });
  });
}

async function ensureFxFresh() {
  if (Date.now() - fxCache.fetched_at < FX_TTL_MS) return fxCache.rate;
  return fetchFxRate();
}

function priceFor(model) {
  if (!model) return PRICING.default;
  if (PRICING[model]) return PRICING[model];
  for (const key of Object.keys(PRICING)) {
    if (key !== 'default' && model.startsWith(key.split('[')[0])) return PRICING[key];
  }
  return PRICING.default;
}

function costUsd(ev) {
  const p = priceFor(ev.model);
  return (
    (ev.input || 0)        * p.in          / 1e6 +
    (ev.output || 0)       * p.out         / 1e6 +
    (ev.cache_read || 0)   * p.cache_read  / 1e6 +
    (ev.cache_create || 0) * p.cache_write / 1e6
  );
}

function ensureDir() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

function appendEvent(ev) {
  ensureDir();
  fs.appendFileSync(EVENTS_FILE, JSON.stringify(ev) + '\n');
}

function readEvents() {
  if (!fs.existsSync(EVENTS_FILE)) return [];
  const txt = fs.readFileSync(EVENTS_FILE, 'utf8');
  const out = [];
  for (const line of txt.split('\n')) {
    if (!line.trim()) continue;
    try { out.push(JSON.parse(line)); } catch {}
  }
  return out;
}

function emptyAgg() {
  return { input: 0, output: 0, cache_read: 0, cache_create: 0, cost_usd: 0, turns: 0 };
}

function accum(agg, ev) {
  agg.input        += ev.input        || 0;
  agg.output       += ev.output       || 0;
  agg.cache_read   += ev.cache_read   || 0;
  agg.cache_create += ev.cache_create || 0;
  agg.cost_usd     += costUsd(ev);
  agg.turns        += 1;
}

function cacheHitPct(a) {
  const total = a.input + a.cache_read + a.cache_create;
  if (total === 0) return 0;
  return (a.cache_read / total) * 100;
}

function tokensPerTurn(a) {
  if (a.turns === 0) return 0;
  return Math.round((a.input + a.output + a.cache_read + a.cache_create) / a.turns);
}

function buildStats(qs) {
  const events = readEvents();
  const now = Date.now() / 1000;
  const ONE_DAY = 86400;
  const sessionId = qs.session_id || null;
  const cwd = qs.cwd || null;

  const session  = emptyAgg();
  const today    = emptyAgg();
  const week     = emptyAgg();
  const month    = emptyAgg();
  const allTime  = emptyAgg();
  const byModel  = {};
  const byProject = {};
  const bySkill   = {};
  const timeline  = [];

  const dayBuckets = new Map();

  for (const ev of events) {
    accum(allTime, ev);

    if (sessionId && ev.session_id === sessionId) accum(session, ev);
    if (now - ev.ts < ONE_DAY)     accum(today, ev);
    if (now - ev.ts < ONE_DAY * 7) accum(week, ev);
    if (now - ev.ts < ONE_DAY * 30) accum(month, ev);

    const m = ev.model || 'unknown';
    byModel[m] = byModel[m] || emptyAgg();
    accum(byModel[m], ev);

    const proj = ev.cwd ? path.basename(ev.cwd) : 'unknown';
    byProject[proj] = byProject[proj] || emptyAgg();
    accum(byProject[proj], ev);

    if (ev.skill) {
      bySkill[ev.skill] = bySkill[ev.skill] || emptyAgg();
      accum(bySkill[ev.skill], ev);
    }

    const dayKey = new Date(ev.ts * 1000).toISOString().slice(0, 10);
    if (!dayBuckets.has(dayKey)) dayBuckets.set(dayKey, emptyAgg());
    accum(dayBuckets.get(dayKey), ev);
  }

  for (const [day, agg] of [...dayBuckets.entries()].sort()) {
    timeline.push({ day, ...agg });
  }

  const rate = fxCache.rate;
  const decorate = a => ({
    ...a,
    cost_brl: a.cost_usd * rate,
    cache_hit_pct: cacheHitPct(a),
    tokens_per_turn: tokensPerTurn(a)
  });

  return {
    session: decorate(session),
    today:   decorate(today),
    week:    decorate(week),
    month:   decorate(month),
    all_time: decorate(allTime),
    by_model:   Object.fromEntries(Object.entries(byModel).map(([k, v]) => [k, decorate(v)])),
    by_project: Object.fromEntries(Object.entries(byProject).map(([k, v]) => [k, decorate(v)])),
    by_skill:   Object.fromEntries(Object.entries(bySkill).map(([k, v]) => [k, decorate(v)])),
    timeline: timeline.map(t => ({ ...t, cost_brl: t.cost_usd * rate })),
    meta: {
      events_count: events.length,
      port: PORT,
      data_file: EVENTS_FILE,
      fx_rate: rate,
      fx_source: fxCache.source,
      fx_fetched_at: fxCache.fetched_at
    }
  };
}

function parseQuery(url) {
  const i = url.indexOf('?');
  if (i === -1) return {};
  const out = {};
  for (const pair of url.slice(i + 1).split('&')) {
    const [k, v] = pair.split('=');
    if (k) out[decodeURIComponent(k)] = decodeURIComponent(v || '');
  }
  return out;
}

function json(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Content-Length': Buffer.byteLength(data)
  });
  res.end(data);
}

const server = http.createServer((req, res) => {
  const urlPath = req.url.split('?')[0];

  if (req.method === 'GET' && urlPath === '/api/health') {
    return json(res, 200, { ok: true, port: PORT, pid: process.pid });
  }

  if (req.method === 'GET' && urlPath === '/api/stats') {
    ensureFxFresh().then(() => {
      try { json(res, 200, buildStats(parseQuery(req.url))); }
      catch (e) { json(res, 500, { error: String(e) }); }
    });
    return;
  }

  if (req.method === 'POST' && urlPath === '/event') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      try {
        const ev = JSON.parse(body);
        if (!ev.ts) ev.ts = Math.floor(Date.now() / 1000);
        appendEvent(ev);
        json(res, 200, { ok: true });
      } catch (e) {
        json(res, 400, { error: String(e) });
      }
    });
    return;
  }

  if (req.method === 'GET' && (urlPath === '/' || urlPath === '/index.html')) {
    if (!fs.existsSync(DASHBOARD_FILE)) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      return res.end('dashboard.html missing');
    }
    const html = fs.readFileSync(DASHBOARD_FILE);
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(html);
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('not found');
});

server.on('error', err => {
  if (err.code === 'EADDRINUSE') {
    console.error(`port ${PORT} already in use`);
    process.exit(2);
  }
  console.error(err);
  process.exit(1);
});

ensureDir();
loadFxCache();
server.listen(PORT, HOST, () => {
  fs.writeFileSync(PID_FILE, String(process.pid));
  console.log(`release-token-worker listening on http://${HOST}:${PORT}`);
  ensureFxFresh().then(r => console.log(`USD→BRL rate: ${r.toFixed(4)} (${fxCache.source})`));
});

const cleanup = () => {
  try { fs.unlinkSync(PID_FILE); } catch {}
  process.exit(0);
};
process.on('SIGTERM', cleanup);
process.on('SIGINT', cleanup);
