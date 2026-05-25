#!/usr/bin/env node
// release-sdk-hook-version: 0.2.0
// django-workflow-guard.js — PreToolUse hook (soft advisory)
//
// Triggers on Write/Edit to Django core files (models.py, serializers.py,
// views.py, viewsets.py, signals.py, tasks.py) when no corresponding test
// file appears recently modified. Nudges the user toward TDD.
//
// Advisory only — never blocks. Disable via env: DJANGO_SDK_WORKFLOW_GUARD=0.

const fs = require('fs');
const path = require('path');

if (process.env.DJANGO_SDK_WORKFLOW_GUARD === '0') {
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

    // Only guard Django core files
    const guardedPatterns = [
      /\/models(\/[^/]+)?\.py$/,
      /\/serializers(\/[^/]+)?\.py$/,
      /\/views(\/[^/]+)?\.py$/,
      /\/viewsets\.py$/,
      /\/signals\.py$/,
      /\/tasks\.py$/,
      /\/permissions\.py$/,
    ];
    const isGuarded = guardedPatterns.some((p) => p.test(filePath));
    if (!isGuarded) process.exit(0);

    // Skip migrations
    if (filePath.includes('/migrations/')) process.exit(0);

    // Heuristic: does a corresponding test file exist?
    // For backend/apps/<app>/models.py, look for backend/apps/<app>/tests/test_models*.py
    const appDir = path.dirname(filePath);
    const fileBase = path.basename(filePath, '.py');
    const testsDir = path.join(appDir, 'tests');

    let hasTest = false;
    if (fs.existsSync(testsDir)) {
      try {
        const testFiles = fs.readdirSync(testsDir);
        hasTest = testFiles.some(
          (f) => f.startsWith(`test_${fileBase}`) || f.startsWith(`test_${fileBase.replace(/s$/, '')}`)
        );
      } catch {}
    }

    if (hasTest) process.exit(0); // Test exists — TDD likely active

    // Emit advisory
    const output = {
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext:
          `⚠️ TDD ADVISORY: Editing ${path.basename(filePath)} but no matching test file found in ${testsDir}. ` +
          `Project convention is TDD (tests before code). Consider:\n` +
          `  1. Write failing test first: tests/test_${fileBase}.py\n` +
          `  2. Commit RED (test failing): \`git commit -m "test(...): add failing test for ${fileBase}"\`\n` +
          `  3. Then implement + commit GREEN.\n` +
          `If this edit is intentional (e.g., quick fix, refactor), proceed normally.`,
      },
    };

    process.stdout.write(JSON.stringify(output));
  } catch {
    process.exit(0);
  }
});
