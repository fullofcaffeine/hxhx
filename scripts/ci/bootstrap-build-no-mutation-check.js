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
  // HxParser owns interpolation and generic declarations before OCaml generation.
  'patch_bootstrap_hxparser_interpolated_exprs',
  'patch-hxparser-interpolated-exprs',
  'patch_bootstrap_hxparser_generic_function_decl',
  'patch-hxparser-generic-function-decl',
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

// Current Haxe emission owns Eof construction. Older cumulative payloads must
// retain their skip markers without synthesizing a second class representation.
const eofPresenceMarker = '(* hxhx(stage3) bootstrap shim: haxe.io.Eof presence repair *)'
const eofPayloads = [
  ['project_generator_helper_calls', 'ProjectGenerator helper-call repair'],
  ['php_syntax_empty_rest_calls', 'Php_Syntax empty-rest repair'],
  ['php_boot_float_zero_compare', 'Php_Boot float zero compare repair'],
  ['php_boot_string_key_lookups', 'Php_Boot string-key lookup repair'],
  ['haxe_io_eof_presence', 'haxe.io.Eof presence repair'],
].map(([name, marker]) => ({name, marker: `(* hxhx(stage3) bootstrap shim: ${marker} *)`}))
const retiredEofSynthesis = ['providerNeedsEof', 'haxe_io_Eof.ml', 'bootstrap shim: haxe.io.Eof *)']
for (const {name} of eofPayloads) {
  const payload = read(path.join(bootstrapPatchPayloadDir, `${name}.mlpatch`))
  for (const token of retiredEofSynthesis) {
    if (payload.includes(token)) {
      fail(`Eof construction belongs to authored Haxe, not bootstrap payload ${name} (found: ${token})`)
    }
  }
  if (payload.split(eofPresenceMarker).length !== 2) {
    fail(`bootstrap payload ${name} must retain exactly one Eof presence marker`)
  }
}
if (read(path.join(bootstrapPatchPayloadDir, 'haxe_io_eof_presence.mlpatch')).trim() !== eofPresenceMarker) {
  fail('the Eof presence payload must remain a marker without generated semantics')
}

// Execute the real shell wrappers and Python insertion helper. Each suffix can
// be the first missing repair in an older snapshot; applying it twice must leave
// one copy of every expected marker and preserve the supported call boundary.
const wrapperStart = finalize.indexOf('run_bootstrap_patch_helper() {')
const wrapperEnd = finalize.indexOf('\nfinalize_bootstrap_dir() {')
if (wrapperStart < 0 || wrapperEnd <= wrapperStart) {
  fail('cannot locate the bootstrap patch function definitions for the Eof regression')
}
const patchDefinitions = finalize.slice(wrapperStart, wrapperEnd)
const eofFixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-bootstrap-eof-'))
try {
  for (const [anchorIndex, shimCall] of [directShimCall, temporaryShimCall].entries()) {
    for (const [firstMissing, {name}] of eofPayloads.entries()) {
      const fixture = path.join(eofFixtureRoot, `${anchorIndex}-${firstMissing}`)
      fs.mkdirSync(fixture)
      const emitterPath = path.join(fixture, 'EmitterStage.ml')
      fs.writeFileSync(emitterPath, [
        'let patchStage3MacroContextLoadShimForStage3 = fun outAbs -> ()',
        ...eofPayloads.slice(0, firstMissing).map(payload => payload.marker),
        shimCall,
        ''
      ].join('\n'))
      const runPatch = () => childProcess.execFileSync('bash', ['-c', [
        'set -euo pipefail',
        'ROOT="$1"',
        'BOOTSTRAP_PATCH_HELPER="$ROOT/scripts/hxhx/bootstrap_patch_helper.py"',
        'BOOTSTRAP_PATCH_PAYLOAD_DIR="$ROOT/scripts/hxhx/bootstrap_patch_payloads"',
        patchDefinitions,
        `patch_bootstrap_emitter_${name} "$2"`
      ].join('\n'), 'bootstrap-eof-fixture', repoRoot, fixture], {encoding: 'utf8'})
      runPatch()
      const once = read(emitterPath)
      for (const {marker} of eofPayloads) {
        if (once.split(marker).length !== 2) {
          throw new Error(`bootstrap suffix ${name} must retain one copy of ${marker}`)
        }
      }
      if (once.split(shimCall).length !== 2 || retiredEofSynthesis.some(token => once.includes(token))) {
        throw new Error(`bootstrap suffix ${name} changed the shim boundary or restored Eof synthesis`)
      }
      runPatch()
      if (read(emitterPath) !== once) {
        throw new Error(`bootstrap suffix ${name} must be byte-identical on repeated application`)
      }
    }
  }
} finally {
  fs.rmSync(eofFixtureRoot, {recursive: true, force: true})
}

for (const token of forbiddenBuildTokens) {
  if (sanitize.includes(token)) {
    fail(`scripts/hxhx/sanitize-stage3-emit-dir.sh must stay cleanup-only for source-lane builds (found: ${token})`)
  }
}

console.log('[ci:guards] OK: bootstrap normal build path is mutation-free, regen owns snapshot finalization, and sanitize stays cleanup-only')
