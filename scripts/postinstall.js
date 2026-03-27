#!/usr/bin/env node
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const cacBin = path.join(__dirname, '..', 'cac');

// Ensure cac is executable
try {
  fs.chmodSync(cacBin, 0o755);
} catch (e) {
  // Windows or insufficient permissions — ignore
}

// Auto-regenerate wrapper + runtime JS files on install/upgrade
// This ensures bug fixes (e.g. dns-guard, wrapper crash) take effect immediately
try {
  execSync('"' + cacBin + '" -v', { stdio: 'ignore', timeout: 10000 });
} catch (e) {
  // First install or no environment yet — fine, _ensure_initialized runs on first cac command
}

console.log(`
  claude-cac installed successfully

  Quick start:
    cac env create <name> [-p <proxy>]   Create an isolated environment
    cac <name>                           Switch environment
    claude                               Start Claude Code

  Docs: https://cac.nextmind.space/docs
`);
