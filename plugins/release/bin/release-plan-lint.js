#!/usr/bin/env node
// Deterministic structural validation for compact and legacy release plans.
const fs = require('fs');
const path = require('path');

const target = process.argv[2];
if (!target) {
  process.stderr.write('usage: release-plan-lint.js <PLAN.md|PLAN-dir>\n');
  process.exit(2);
}

function markdownFiles(p) {
  const stat = fs.statSync(p);
  if (stat.isFile()) return [p];
  return fs.readdirSync(p).filter(n => n.endsWith('.md')).sort().map(n => path.join(p, n));
}

const findings = [];
const tasks = new Map();
let files;
try { files = markdownFiles(target); }
catch (error) {
  process.stderr.write(`PLAN_LINT=FAIL missing=${target}\n`);
  process.exit(1);
}

for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split('\n');
  if (lines.length > 600) findings.push(`${file}: plan slice exceeds 600 lines`);
  const headings = [...text.matchAll(/^###\s+(T\d+)\s*(?:[—:-]|$).*$/gm)];
  for (let i = 0; i < headings.length; i++) {
    const id = headings[i][1];
    const start = headings[i].index;
    const end = i + 1 < headings.length ? headings[i + 1].index : text.length;
    const body = text.slice(start, end);
    if (tasks.has(id)) findings.push(`${file}: duplicate task ${id}`);
    const depMatch = body.match(/^\s*-?\s*depends_on:\s*\[([^\]]*)\]/m);
    const deps = depMatch ? depMatch[1].split(',').map(x => x.trim()).filter(Boolean) : [];
    if (!/(^|\n)\s*(?:-\s*)?(?:files?|paths?):/im.test(body)) findings.push(`${file}: ${id} missing files`);
    if (!/(^|\n)\s*(?:-\s*)?(?:verify|verification):/im.test(body)) findings.push(`${file}: ${id} missing verification`);
    tasks.set(id, { file, deps });
  }
}

if (tasks.size === 0) findings.push(`${target}: no Txx tasks found`);
for (const [id, task] of tasks) {
  for (const dep of task.deps) if (!tasks.has(dep)) findings.push(`${task.file}: ${id} depends on missing ${dep}`);
}

const visiting = new Set();
const visited = new Set();
function visit(id, chain = []) {
  if (visiting.has(id)) { findings.push(`${tasks.get(id).file}: dependency cycle ${[...chain, id].join(' -> ')}`); return; }
  if (visited.has(id) || !tasks.has(id)) return;
  visiting.add(id);
  for (const dep of tasks.get(id).deps) visit(dep, [...chain, id]);
  visiting.delete(id); visited.add(id);
}
for (const id of tasks.keys()) visit(id);

if (findings.length) {
  process.stdout.write('PLAN_LINT=FAIL\n' + findings.map(x => `- ${x}`).join('\n') + '\n');
  process.exit(1);
}
process.stdout.write(`PLAN_LINT=PASS tasks=${tasks.size} files=${files.length}\n`);
