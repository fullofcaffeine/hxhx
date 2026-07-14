#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const buildScript = path.join(repoRoot, 'scripts', 'hxhx', 'build-hxhx.sh')
const regenScript = path.join(repoRoot, 'scripts', 'hxhx', 'regenerate-hxhx-bootstrap.sh')
const copyScript = path.join(repoRoot, 'scripts', 'hxhx', 'copy-bootstrap-snapshot.sh')
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
const copy = read(copyScript)
const sanitize = read(sanitizeScript)
const finalize = read(finalizeScript)
const bootstrapPatchHelper = read(path.join(repoRoot, 'scripts', 'hxhx', 'bootstrap_patch_helper.py'))

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
if (!regen.includes('copy-bootstrap-snapshot.sh')) {
  fail('scripts/hxhx/regenerate-hxhx-bootstrap.sh must use the tested snapshot-copy boundary')
}
if (!copy.includes("--exclude='hxhx-current-source.env'")) {
  fail('bootstrap snapshot copying must exclude the current-source build receipt')
}

const retiredBootstrapPatchTokens = [
  'patch_bootstrap_js_target_core_native_js_lib_externs',
  'patch-js-target-core-native-js-lib-externs',
  'js.lib extern native global repair',
]
for (const token of retiredBootstrapPatchTokens) {
  if (finalize.includes(token) || bootstrapPatchHelper.includes(token)) {
    fail(`retired bootstrap JsTargetCore js.lib extern patch must not be restored (found: ${token})`)
  }
}

for (const token of forbiddenBuildTokens) {
  if (sanitize.includes(token)) {
    fail(`scripts/hxhx/sanitize-stage3-emit-dir.sh must stay cleanup-only for source-lane builds (found: ${token})`)
  }
}

console.log('[ci:guards] OK: bootstrap normal build path is mutation-free, regen owns snapshot finalization, and sanitize stays cleanup-only')
