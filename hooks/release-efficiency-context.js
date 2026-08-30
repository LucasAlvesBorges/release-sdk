#!/usr/bin/env node
'use strict';

// Inject the release-sdk efficiency policy once per session and once per
// subagent. It is deliberately advisory and never writes runtime state.

const fs = require('fs');
const path = require('path');

const event = process.argv[2] === 'SubagentStart' ? 'SubagentStart' : 'SessionStart';

function executableOnPath(name) {
  const directories = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const extensions = process.platform === 'win32'
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';')
    : [''];

  return directories.some((directory) => extensions.some((extension) => {
    const candidate = path.join(directory, `${name}${extension}`);
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }));
}

function loadContext() {
  try {
    const policy = fs.readFileSync(
      path.join(__dirname, 'release-efficiency-policy.md'),
      'utf8',
    ).trim();
    const runtime = executableOnPath('rtk')
      ? '\n<release_efficiency_runtime>RTK detected on PATH; use it under the safeguards above.</release_efficiency_runtime>'
      : '';
    return `${policy}${runtime}`;
  } catch {
    return '';
  }
}

const context = loadContext();
if (!context) process.exit(0);

if (process.env.PLUGIN_DATA) {
  process.stdout.write(JSON.stringify({
    systemMessage: 'RELEASE_EFFICIENCY_ACTIVE',
    hookSpecificOutput: {
      hookEventName: event,
      additionalContext: context,
    },
  }));
} else if (event === 'SubagentStart') {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: event,
      additionalContext: context,
    },
  }));
} else {
  process.stdout.write(context);
}
