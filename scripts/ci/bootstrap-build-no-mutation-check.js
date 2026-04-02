#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const buildScript = path.join(repoRoot, 'scripts', 'hxhx', 'build-hxhx.sh')
const regenScript = path.join(repoRoot, 'scripts', 'hxhx', 'regenerate-hxhx-bootstrap.sh')
const sanitizeScript = path.join(repoRoot, 'scripts', 'hxhx', 'sanitize-stage3-emit-dir.sh')
const finalizeScript = path.join(repoRoot, 'scripts', 'hxhx', 'finalize-bootstrap-dir.sh')

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exit(1)
}

function read(file) {
  return fs.readFileSync(file, 'utf8')
}

const build = read(buildScript)
const regen = read(regenScript)
const sanitize = read(sanitizeScript)

if (!fs.existsSync(finalizeScript)) {
  fail('missing scripts/hxhx/finalize-bootstrap-dir.sh')
}

const forbiddenBuildTokens = [
  'bootstrap_patch_helper.py',
  'bootstrap_patch_payloads',
  'patch_bootstrap_',
  'run_bootstrap_patch_helper',
  'insert_bootstrap_patch_before_anchor'
]
for (const token of forbiddenBuildTokens) {
  if (build.includes(token)) {
    fail(`scripts/hxhx/build-hxhx.sh must stay mutation-free for committed bootstrap snapshots (found: ${token})`)
  }
}

if (!regen.includes('finalize-bootstrap-dir.sh')) {
  fail('scripts/hxhx/regenerate-hxhx-bootstrap.sh must finalize bootstrap_out before sharding')
}

if (!sanitize.includes('bootstrap_patch_helper.py')) {
  fail('scripts/hxhx/sanitize-stage3-emit-dir.sh unexpectedly stopped being the explicit source-lane mutation boundary')
}

console.log('[ci:guards] OK: bootstrap normal build path is mutation-free and regen owns snapshot finalization')
