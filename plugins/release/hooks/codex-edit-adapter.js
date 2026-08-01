#!/usr/bin/env node
'use strict';

// Adapts Codex apply_patch hook payloads to the legacy Write/Edit payload shape
// consumed by release-sdk's existing advisory hooks. This file exists only in
// the generated Codex package; Claude Code continues using the original hooks.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

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

function patchEdits(command) {
  const header = /^\*\*\* (Add|Update|Delete) File: (.+)$/gm;
  const matches = [...command.matchAll(header)];
  if (matches.length === 0) return [];

  return matches.map((match, index) => {
    const start = match.index + match[0].length;
    const end = index + 1 < matches.length ? matches[index + 1].index : command.length;
    return {
      operation: match[1],
      filePath: match[2].trim(),
      content: command.slice(start, end).replace(/\n\*\*\* End Patch\s*$/, ''),
    };
  });
}

function runTarget(target, payload) {
  const ext = path.extname(target);
  const executable = ext === '.sh' ? 'bash' : process.execPath;
  const result = spawnSync(executable, [target], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    timeout: 7000,
    env: process.env,
  });

  if (result.error || !result.stdout) return [];
  return result.stdout
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .flatMap((line) => {
      try {
        return [JSON.parse(line)];
      } catch {
        return [];
      }
    });
}

function extractMessages(outputs) {
  const messages = [];
  for (const output of outputs) {
    const context =
      output?.hookSpecificOutput?.additionalContext ||
      output?.additionalContext ||
      output?.systemMessage ||
      output?.reason;
    if (typeof context === 'string' && context.trim()) messages.push(context.trim());
  }
  return [...new Set(messages)];
}

async function main() {
  const target = process.argv[2];
  if (!target || !fs.existsSync(target)) return;

  const raw = await readStdin();
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return;
  }

  let payloads = [payload];
  if (payload.tool_name === 'apply_patch') {
    const command = payload.tool_input?.command || '';
    const edits = patchEdits(command);
    payloads = edits.map((edit) => ({
      ...payload,
      tool_name: 'Edit',
      tool_input: {
        ...payload.tool_input,
        file_path: edit.filePath,
        path: edit.filePath,
        content: edit.content,
        new_string: edit.content,
        codex_patch_operation: edit.operation,
      },
    }));
  }

  const outputs = payloads.flatMap((item) => runTarget(target, item));
  const messages = extractMessages(outputs);
  if (messages.length === 0) return;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext: messages.join('\n\n'),
      },
    })
  );
}

main().catch(() => {});
