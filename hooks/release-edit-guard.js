#!/usr/bin/env node
// release-sdk-hook-version: 0.3.0
// One advisory pass for planning injection, tenant scope, frontend security,
// and missing focused tests. Replaces five processes on every edit.

const fs = require('fs');
const path = require('path');

const injectionPatterns = [
  /ignore\s+(all\s+)?(previous|above)\s+instructions/i,
  /disregard\s+(all\s+)?previous/i,
  /forget\s+(all\s+)?(your\s+)?instructions/i,
  /override\s+(system|previous)\s+(prompt|instructions)/i,
  /(?:reveal|show|print|repeat)\s+(your\s+)?(system\s+)?(prompt|instructions)/i,
  /<\/?(?:system|assistant|human)>|\[SYSTEM\]|\[INST\]|<<\s*SYS\s*>>/i,
  /[\u200B-\u200F\u2028-\u202F\uFEFF\u00AD]/u,
];

const frontendSecurityPatterns = [
  ['AUTH_TOKEN_STORAGE', /(?:local|session)Storage\s*\.\s*setItem\s*\(\s*['"`][^'"`]*(?:token|auth|jwt|access|refresh|credential)/i,
    'Do not store auth tokens in Web Storage; prefer Secure HttpOnly cookies.'],
  ['DANGEROUS_HTML', /dangerouslySetInnerHTML\s*=\s*\{\s*\{|\.innerHTML\s*=/,
    'Sanitize untrusted HTML or render it as text/JSX.'],
  ['EVAL', /\beval\s*\(/, 'Avoid eval(); use a typed parser or explicit dispatch.'],
  ['HARDCODED_SECRET', /(api[_-]?key|secret|password|private[_-]?key)\s*[:=]\s*['"`][A-Za-z0-9+/=_-]{16,}['"`]/i,
    'Move secrets out of source control.'],
  ['OPEN_REDIRECT', /window\.location\s*(?:\.href\s*=|\.replace\s*\()\s*[^'"`\n]{0,20}(?:params|query|search|url|redirect)/i,
    'Validate dynamic redirect targets against an internal allowlist.'],
];

function exists(candidate) {
  try { return fs.existsSync(candidate); } catch { return false; }
}

function djangoTestMissing(filePath) {
  if (process.env.DJANGO_SDK_WORKFLOW_GUARD === '0') return false;
  const guarded = [
    /\/models(?:\/[^/]+)?\.py$/, /\/serializers(?:\/[^/]+)?\.py$/,
    /\/views(?:\/[^/]+)?\.py$/, /\/viewsets\.py$/, /\/signals\.py$/,
    /\/tasks\.py$/, /\/permissions\.py$/,
  ].some((pattern) => pattern.test(filePath));
  if (!guarded || filePath.includes('/migrations/')) return false;

  const dir = path.dirname(filePath);
  const base = path.basename(filePath, '.py');
  const testsDir = path.join(dir, 'tests');
  try {
    return !fs.readdirSync(testsDir).some((name) =>
      name.startsWith(`test_${base}`) || name.startsWith(`test_${base.replace(/s$/, '')}`));
  } catch {
    return true;
  }
}

function reactTestMissing(filePath) {
  if (process.env.RELEASE_SDK_REACT_GUARD === '0') return false;
  if (/\.(test|spec)\./.test(filePath) || filePath.includes('/__tests__/')) return false;
  const guarded = [
    /\/(components|pages|screens|views|containers)\/[^/]+\.tsx$/,
    /\/hooks\/use[A-Z][^/]+\.tsx?$/,
    /\/features\/[^/]+\/[^/]+\.tsx$/,
  ].some((pattern) => pattern.test(filePath));
  if (!guarded) return false;

  const dir = path.dirname(filePath);
  const base = path.basename(filePath).replace(/\.(tsx|ts)$/, '');
  return ![
    `${base}.test.tsx`, `${base}.test.ts`, `${base}.spec.tsx`, `${base}.spec.ts`,
    path.join('__tests__', `${base}.test.tsx`), path.join('__tests__', `${base}.test.ts`),
  ].some((name) => exists(path.join(dir, name)));
}

function inspect(data) {
  if (!['Write', 'Edit'].includes(data.tool_name)) return [];
  const toolInput = data.tool_input || {};
  const filePath = toolInput.file_path || toolInput.path || '';
  const content = toolInput.content || toolInput.new_string || '';
  if (!filePath) return [];
  const normalizedPath = filePath.replace(/\\/g, '/');

  const messages = [];
  const planning = normalizedPath.includes('.release-planning/') ||
    normalizedPath.includes('.planning/') ||
    /\/(?:\d+-)?(?:PLAN|SPEC|CONTEXT|RESEARCH)\.md$/.test(normalizedPath);
  if (planning && content) {
    const hits = injectionPatterns.filter((pattern) => pattern.test(content)).length;
    if (hits) messages.push(`PROMPT INJECTION: ${hits} suspicious pattern(s) in ${path.basename(filePath)}; review embedded instructions.`);
  }

  const modelsFile = /models(?:\/[^/]+)?\.py$/.test(normalizedPath) && !normalizedPath.includes('/migrations/');
  if (modelsFile && content && !content.includes('django-sdk: no-tenant-check')) {
    const directModels = content.match(/^class\s+[A-Z][A-Za-z0-9_]*\([^\n)]*models\.Model[^\n)]*\)/gm) || [];
    const unsafe = directModels.filter((line) => !/(TenantModel|RLSModel|AbstractBaseUser|AbstractUser)/.test(line));
    if (unsafe.length) messages.push(`TENANT SCOPE: ${unsafe.length} direct models.Model subclass(es); use TenantModel or add the documented opt-out.`);
  }

  const frontend = !normalizedPath.endsWith('/hooks/release-edit-guard.js') &&
    /\.(tsx|ts|jsx|js)$/.test(normalizedPath) &&
    !/(\/node_modules\/|\.(test|spec)\.|\/__tests__\/|\.d\.ts$)/.test(normalizedPath);
  if (frontend && content && process.env.RELEASE_SDK_REACT_SEC_GUARD !== '0') {
    for (const [code, pattern, advice] of frontendSecurityPatterns) {
      if (pattern.test(content)) messages.push(`${code}: ${advice}`);
    }
  }

  const subagent = toolInput.is_subagent || data.session_type === 'task';
  if (!subagent && djangoTestMissing(normalizedPath)) {
    messages.push(`FOCUSED TEST: no matching Django test found for ${path.basename(filePath)}; add one when behavior changes.`);
  }
  if (!subagent && reactTestMissing(normalizedPath)) {
    messages.push(`FOCUSED TEST: no matching React test found for ${path.basename(filePath)}; add one when behavior changes.`);
  }
  return messages;
}

let input = '';
const timeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  clearTimeout(timeout);
  try {
    const messages = inspect(JSON.parse(input));
    if (!messages.length) return;
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext: `release-sdk advisory:\n- ${messages.join('\n- ')}`,
      },
    }));
  } catch {
    process.exitCode = 0;
  }
});
