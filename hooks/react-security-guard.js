#!/usr/bin/env node
// release-sdk-hook-version: 0.2.0
// react-security-guard.js — PreToolUse hook (advisory)
//
// Scans Write/Edit content on .tsx/.ts/.jsx/.js files for React security
// anti-patterns: localStorage/sessionStorage auth tokens, dangerouslySetInnerHTML
// without sanitization, hardcoded secrets, raw innerHTML assignment.
//
// Advisory only — never blocks. Disable via env: RELEASE_SDK_REACT_SEC_GUARD=0.

if (process.env.RELEASE_SDK_REACT_SEC_GUARD === '0') {
  process.exit(0);
}

const REACT_SECURITY_PATTERNS = [
  {
    // localStorage storing token/auth
    pattern: /localStorage\s*\.\s*setItem\s*\(\s*['"`][^'"`]*(token|auth|jwt|access|refresh|session|credential)[^'"`]*['"`]/i,
    code: 'AUTH_TOKEN_LOCALSTORAGE',
    message:
      '🔴 AUTH TOKEN IN localStorage: Tokens in localStorage are accessible to any JS (XSS-vulnerable). ' +
      'Use httpOnly cookies instead. The Django backend should set Set-Cookie: token=...; HttpOnly; Secure; SameSite=Strict.',
  },
  {
    // sessionStorage storing token/auth
    pattern: /sessionStorage\s*\.\s*setItem\s*\(\s*['"`][^'"`]*(token|auth|jwt|access|refresh|session|credential)[^'"`]*['"`]/i,
    code: 'AUTH_TOKEN_SESSIONSTORAGE',
    message:
      '🔴 AUTH TOKEN IN sessionStorage: sessionStorage is XSS-vulnerable (readable by any script). ' +
      'Use httpOnly cookies for auth tokens.',
  },
  {
    // dangerouslySetInnerHTML without DOMPurify
    pattern: /dangerouslySetInnerHTML\s*=\s*\{\s*\{/,
    code: 'DANGEROUS_INNER_HTML',
    message:
      '⚠️ dangerouslySetInnerHTML DETECTED: Ensure content is sanitized with DOMPurify before rendering. ' +
      'Pattern: `dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(content) }}`. ' +
      'Unsanitized user input here = stored XSS.',
  },
  {
    // Direct innerHTML assignment (not JSX but mixed files)
    pattern: /\.innerHTML\s*=/,
    code: 'INNER_HTML_ASSIGNMENT',
    message:
      '⚠️ innerHTML ASSIGNMENT: Direct DOM innerHTML is XSS-prone. ' +
      'Use React JSX or sanitize with DOMPurify.sanitize() before assignment.',
  },
  {
    // eval() usage
    pattern: /\beval\s*\(/,
    code: 'EVAL_USAGE',
    message:
      '🔴 eval() USAGE: eval() executes arbitrary code — code injection risk. ' +
      'Replace with JSON.parse() for data, or a safe alternative.',
  },
  {
    // Hardcoded secrets (basic heuristic)
    pattern: /(api[_-]?key|secret|password|private[_-]?key)\s*[:=]\s*['"`][A-Za-z0-9+/=_\-]{16,}['"`]/i,
    code: 'HARDCODED_SECRET',
    message:
      '🔴 POTENTIAL HARDCODED SECRET: String matching API key / secret pattern found in source. ' +
      'Use environment variables (import.meta.env.VITE_*) and never commit secrets to source.',
  },
  {
    // window.location.href with user input (open redirect)
    pattern: /window\.location\s*(?:\.href\s*=|\.replace\s*\()\s*[^'"`\n]{0,20}(?:params|query|search|url|redirect)/i,
    code: 'OPEN_REDIRECT',
    message:
      '⚠️ POTENTIAL OPEN REDIRECT: window.location assignment from dynamic source. ' +
      'Validate redirect targets against an allowlist of internal paths.',
  },
];

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => (input += chunk));
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);
    const toolName = data.tool_name;
    if (toolName !== 'Write' && toolName !== 'Edit') process.exit(0);

    const filePath = data.tool_input?.file_path || '';

    // Only scan frontend source files
    const isFrontend = /\.(tsx|ts|jsx|js)$/.test(filePath) &&
      !filePath.includes('/node_modules/') &&
      !filePath.includes('.test.') &&
      !filePath.includes('.spec.') &&
      !filePath.includes('__tests__') &&
      !filePath.endsWith('.d.ts');

    if (!isFrontend) process.exit(0);

    const content = data.tool_input?.content || data.tool_input?.new_string || '';
    if (!content) process.exit(0);

    const findings = [];
    for (const { pattern, code, message } of REACT_SECURITY_PATTERNS) {
      if (pattern.test(content)) {
        findings.push({ code, message });
      }
    }

    if (findings.length === 0) process.exit(0);

    const lines = findings.map((f) => `  [${f.code}] ${f.message}`).join('\n');

    const output = {
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext:
          `⚠️ REACT SECURITY ADVISORY: ${findings.length} issue(s) detected in ${require('path').basename(filePath)}:\n` +
          lines +
          `\n\nReview before committing. Run /release:security for full audit.`,
      },
    };

    process.stdout.write(JSON.stringify(output));
  } catch {
    process.exit(0);
  }
});
