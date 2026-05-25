#!/usr/bin/env node
// release-sdk-hook-version: 0.2.0
// react-workflow-guard.js — PreToolUse hook (soft advisory)
//
// Triggers on Write/Edit to React component/hook files (.tsx, .ts hooks)
// when no corresponding test file appears to exist. Nudges toward TDD.
//
// Advisory only — never blocks. Disable via env: RELEASE_SDK_REACT_GUARD=0.

const fs = require('fs');
const path = require('path');

if (process.env.RELEASE_SDK_REACT_GUARD === '0') {
  process.exit(0);
}

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => (input += chunk));
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const toolName = data.tool_name;

    if (toolName !== 'Write' && toolName !== 'Edit') {
      process.exit(0);
    }

    const filePath = data.tool_input?.file_path || data.tool_input?.path || '';
    if (!filePath) process.exit(0);

    // Subagent context — skip (subagent is the test writer, presumably)
    if (data.tool_input?.is_subagent || data.session_type === 'task') {
      process.exit(0);
    }

    // Only guard React component and hook files
    const guardedPatterns = [
      /\/components\/[^/]+\.tsx$/,
      /\/pages\/[^/]+\.tsx$/,
      /\/screens\/[^/]+\.tsx$/,
      /\/views\/[^/]+\.tsx$/,
      /\/hooks\/use[A-Z][^/]+\.ts$/,
      /\/hooks\/use[A-Z][^/]+\.tsx$/,
      /\/features\/[^/]+\/[^/]+\.tsx$/,
      /\/containers\/[^/]+\.tsx$/,
    ];
    const isGuarded = guardedPatterns.some((p) => p.test(filePath));
    if (!isGuarded) process.exit(0);

    // Skip test files themselves
    if (filePath.includes('.test.') || filePath.includes('.spec.') || filePath.includes('__tests__')) {
      process.exit(0);
    }

    // Heuristic: does a corresponding test file exist?
    const dir = path.dirname(filePath);
    const base = path.basename(filePath).replace(/\.(tsx|ts)$/, '');

    // Look in same dir and __tests__ subdir
    const candidates = [
      path.join(dir, `${base}.test.tsx`),
      path.join(dir, `${base}.test.ts`),
      path.join(dir, `${base}.spec.tsx`),
      path.join(dir, `${base}.spec.ts`),
      path.join(dir, '__tests__', `${base}.test.tsx`),
      path.join(dir, '__tests__', `${base}.test.ts`),
    ];

    const hasTest = candidates.some((c) => {
      try { return fs.existsSync(c); } catch { return false; }
    });

    if (hasTest) process.exit(0);

    const isHook = /\/hooks\/use[A-Z]/.test(filePath);
    const type = isHook ? 'hook' : 'component';

    const output = {
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext:
          `⚠️ TDD ADVISORY (React): Editing ${path.basename(filePath)} but no matching test file found. ` +
          `Project convention is TDD (tests before code). Consider:\n` +
          `  1. Write failing test first: ${base}.test.tsx\n` +
          `  2. Commit RED: \`git commit -m "test(ui): add failing test for ${base}"\`\n` +
          `  3. Implement ${type} + commit GREEN: \`git commit -m "feat(ui): implement ${base}"\`\n` +
          `Use Vitest + React Testing Library. If intentional (quick fix, refactor), proceed normally.`,
      },
    };

    process.stdout.write(JSON.stringify(output));
  } catch {
    process.exit(0);
  }
});
