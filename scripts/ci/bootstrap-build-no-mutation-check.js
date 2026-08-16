#!/usr/bin/env node
const fs = require('fs')
const os = require('os')
const path = require('path')
const childProcess = require('child_process')

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
const bootstrapPatchHelperPath = path.join(repoRoot, 'scripts', 'hxhx', 'bootstrap_patch_helper.py')
const bootstrapPatchPayloadDir = path.join(repoRoot, 'scripts', 'hxhx', 'bootstrap_patch_payloads')

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
  'patch_bootstrap_stage1_std_root_termination',
  'patch-stage1-std-root-termination',
  'bootstrap Stage1 std-root repair',
]
for (const token of retiredBootstrapPatchTokens) {
  if (finalize.includes(token) || bootstrapPatchHelper.includes(token)) {
    fail(`retired generated bootstrap repair must not be restored (found: ${token})`)
  }
}

const retiredBootstrapPatchCommands = [
  'patch-instance-call-receiver-forwarding',
  'patch-instance-call-this-binding',
  'patch-instance-method-value-binding',
  'patch-instance-call-preapplied-arity',
  'patch-emitter-preapplied-sig-fallback',
  'patch-plugin-dune-layout',
  'patch-typerstage-lowercase-static-receiver-guard',
  'patch-hxparser-uppercase-helper-call',
]
for (const command of retiredBootstrapPatchCommands) {
  if (finalize.includes(command) || bootstrapPatchHelper.includes(`"${command}":`)) {
    fail(`source-owned Stage3 instance-call behavior must not be restored as an active bootstrap repair (found: ${command})`)
  }
}

const retiredBootstrapPatchPayloads = [
  'root_sys_stdio.mlpatch',
]
for (const payload of retiredBootstrapPatchPayloads) {
  if (finalize.includes(payload) || fs.existsSync(path.join(bootstrapPatchPayloadDir, payload))) {
    fail(`source-owned bootstrap behavior must not be restored through a generated payload (found: ${payload})`)
  }
}

function findEmitterShimPatchAnchor(source) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-bootstrap-anchor-'))
  const sourcePath = path.join(tempRoot, 'EmitterStage.ml')
  try {
    fs.writeFileSync(sourcePath, source)
    return childProcess.execFileSync('python3', [
      bootstrapPatchHelperPath,
      'find-emitter-shim-patch-anchor',
      sourcePath
    ], {encoding: 'utf8'})
  } finally {
    fs.rmSync(tempRoot, {recursive: true, force: true})
  }
}

const directShimCall =
  '  ignore (patchStage3MacroContextLoadShimForStage3 (outAbs : string));'
if (findEmitterShimPatchAnchor([
  'let patchStage3MacroContextLoadShimForStage3 = fun outAbs -> ()',
  directShimCall
].join('\n')) !== directShimCall) {
  fail('bootstrap finalizer must retain the direct macro-context shim call as its payload boundary')
}

const temporaryShimCall =
  '  ignore (let __call_arg_0_3957 = outAbs in patchStage3MacroContextLoadShimForStage3 __call_arg_0_3957);'
if (findEmitterShimPatchAnchor([
  'let patchStage3MacroContextLoadShimForStage3 = fun outAbs -> ()',
  temporaryShimCall
].join('\n')) !== temporaryShimCall) {
  fail('bootstrap finalizer must accept numbered call-argument temporaries without guessing their suffix')
}

for (const token of forbiddenBuildTokens) {
  if (sanitize.includes(token)) {
    fail(`scripts/hxhx/sanitize-stage3-emit-dir.sh must stay cleanup-only for source-lane builds (found: ${token})`)
  }
}

console.log('[ci:guards] OK: bootstrap normal build path is mutation-free, regen owns snapshot finalization, and sanitize stays cleanup-only')
