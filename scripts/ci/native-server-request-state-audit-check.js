#!/usr/bin/env node
/**
 * Keep process-wide Haxe fields visible to the native server lifecycle review.
 *
 * A native hxhx server handles many compiler requests in one process. A Haxe
 * `static var` or a mutable object stored in `static final` can therefore carry
 * data from one request into the next. The checked inventory explains every
 * such declaration in production hxhx/core sources. Adding one requires an
 * explicit review of whether it is immutable process configuration or which
 * request cleanup owns it.
 */

const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const auditPath = path.join(root, 'docs/00-project/NATIVE_SERVER_REQUEST_STATE_AUDIT.json')
const audit = JSON.parse(fs.readFileSync(auditPath, 'utf8'))
const declarationPattern = /^\s*(?:(?:public|private)\s+)?static\s+(var|final)\s+([A-Za-z_][A-Za-z0-9_]*)/

function fail(message) {
  console.error(`[native-server-request-state-audit] ERROR: ${message}`)
  process.exit(1)
}

function haxeFiles(directory) {
  const files = []
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name)
    if (entry.isDirectory()) files.push(...haxeFiles(absolute))
    else if (entry.isFile() && entry.name.endsWith('.hx')) files.push(absolute)
  }
  return files
}

if (audit.schema !== 'hxhx-native-server-request-state-audit.v3') fail('unsupported or missing audit schema')
if (!Array.isArray(audit.scope) || audit.scope.length === 0) fail('audit scope must list source directories')
if (!Array.isArray(audit.entries) || audit.entries.length === 0) fail('audit entries must not be empty')
if (!audit.lifecycle_policy || typeof audit.lifecycle_policy !== 'object') fail('audit must define lifecycle_policy')
if (typeof audit.lifecycle_policy.reusable_payload_rule !== 'string' || audit.lifecycle_policy.reusable_payload_rule.length === 0) {
  fail('lifecycle_policy must state the reusable payload rule')
}
if (!Array.isArray(audit.lifecycle_policy.compatibility_lanes) || audit.lifecycle_policy.compatibility_lanes.length === 0) {
  fail('lifecycle_policy must classify compatibility lanes')
}
if (!Array.isArray(audit.lifecycle_policy.request_lifecycle_owners) || audit.lifecycle_policy.request_lifecycle_owners.length === 0) {
  fail('lifecycle_policy must classify separate request lifecycle owners')
}

const observed = new Map()
for (const relativeRoot of audit.scope) {
  const sourceRoot = path.join(root, relativeRoot)
  for (const file of haxeFiles(sourceRoot)) {
    const declarations = []
    for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      const match = declarationPattern.exec(line)
      if (match) declarations.push(`${match[1]}:${match[2]}`)
    }
    if (declarations.length > 0) observed.set(path.relative(root, file).split(path.sep).join('/'), declarations)
  }
}

const expected = new Map()
for (const entry of audit.entries) {
  if (!entry || typeof entry.path !== 'string') fail('every audit entry needs a path')
  if (!Array.isArray(entry.immutable_fields) || !Array.isArray(entry.request_reset_fields)) {
    fail(`${entry.path} must classify immutable_fields and request_reset_fields`)
  }
  if (expected.has(entry.path)) fail(`duplicate audit entry for ${entry.path}`)

  const declarations = [...entry.immutable_fields, ...entry.request_reset_fields]
  if (declarations.length === 0) fail(`${entry.path} must classify at least one process-wide field`)
  for (const declaration of declarations) {
    if (typeof declaration !== 'string' || !/^(?:var|final):[A-Za-z_][A-Za-z0-9_]*$/.test(declaration)) {
      fail(`${entry.path} has invalid field descriptor ${JSON.stringify(declaration)}`)
    }
  }
  if (new Set(declarations).size !== declarations.length) fail(`${entry.path} classifies a field more than once`)
  if (entry.request_reset_fields.length > 0 && (typeof entry.reset_owner !== 'string' || entry.reset_owner.length === 0)) {
    fail(`${entry.path} must name the request reset owner`)
  }
  if (entry.request_reset_fields.length === 0 && entry.reset_owner !== null) {
    fail(`${entry.path} has no request fields, so reset_owner must be null`)
  }
  if (typeof entry.reason !== 'string' || entry.reason.length === 0) fail(`${entry.path} must explain its classification`)
  expected.set(entry.path, declarations)
}

for (const [file, declarations] of observed) {
  if (!expected.has(file)) fail(`${file} declares ${declarations.length} process-wide field(s) but is missing from the audit`)
  const reviewed = expected.get(file)
  const reviewedSet = new Set(reviewed)
  const missing = declarations.filter(declaration => !reviewedSet.has(declaration))
  const observedSet = new Set(declarations)
  const stale = reviewed.filter(declaration => !observedSet.has(declaration))
  if (reviewed.length !== declarations.length || missing.length > 0 || stale.length > 0) {
    fail(`${file} field inventory differs; missing from audit: ${missing.join(', ') || 'none'}; no longer declared: ${stale.join(', ') || 'none'}`)
  }
}
for (const [file] of expected) {
  if (!observed.has(file)) fail(`${file} is audited but no longer declares a process-wide field`)
}

const requestStatePaths = new Set(
  audit.entries.filter(entry => entry.request_reset_fields.length > 0).map(entry => entry.path)
)
const lifecyclePaths = new Map()
function classifyLifecycle(owner, category) {
  if (!owner || !Array.isArray(owner.paths) || owner.paths.length === 0) fail(`${category} must list at least one path`)
  if (typeof owner.kind !== 'string' || owner.kind.length === 0) fail(`${category} must name its kind`)
  if (typeof owner.lifecycle_owner !== 'string' || owner.lifecycle_owner.length === 0) fail(`${category} must name its lifecycle owner`)
  if (typeof owner.cache_eligibility !== 'string' || owner.cache_eligibility.length === 0) fail(`${category} must state cache eligibility`)
  for (const file of owner.paths) {
    if (lifecyclePaths.has(file)) fail(`${file} has more than one lifecycle classification`)
    lifecyclePaths.set(file, category)
  }
}
for (const lane of audit.lifecycle_policy.compatibility_lanes) classifyLifecycle(lane, `compatibility lane ${lane.kind || '<unknown>'}`)
for (const owner of audit.lifecycle_policy.request_lifecycle_owners) classifyLifecycle(owner, `request lifecycle ${owner.kind || '<unknown>'}`)
for (const file of requestStatePaths) {
  if (!lifecyclePaths.has(file)) fail(`${file} has request-reset fields but no lifecycle classification`)
}
for (const file of lifecyclePaths.keys()) {
  if (!requestStatePaths.has(file)) fail(`${file} has a lifecycle classification but no request-reset fields`)
}

const stage3Lane = audit.lifecycle_policy.compatibility_lanes.find(lane => lane.kind === 'duplicate-stage3-ocaml-emitter')
if (!stage3Lane) fail('lifecycle_policy must classify the duplicate Stage3 OCaml emitter')
if (stage3Lane.paths.length !== 1 || stage3Lane.paths[0] !== 'packages/hxhx-core/src/EmitterStage.hx') {
  fail('the duplicate Stage3 OCaml compatibility lane must contain only EmitterStage')
}
if (stage3Lane.execution !== 'serialized' || stage3Lane.cache_eligibility !== 'never') {
  fail('the duplicate Stage3 OCaml emitter must stay serialized and cache-ineligible')
}
if (stage3Lane.readiness_eligibility !== 'bootstrap-diagnostic-only' || stage3Lane.retirement_owner !== 'haxe_ocaml-38gsp.1') {
  fail('the duplicate Stage3 OCaml emitter must remain diagnostic-only under haxe_ocaml-38gsp.1')
}

for (const entry of audit.entries) {
  if (
    entry.request_reset_fields.length > 0
    && (entry.path.startsWith('packages/hxhx-core/src/backend/source/')
      || entry.path.startsWith('packages/hxhx-core/src/backend/cpp/'))
  ) {
    fail(`${entry.path} restores request-sensitive state to a migrated production target renderer`)
  }
}

const staticOwner = fs.readFileSync(path.join(root, 'packages/hxhx-core/src/CompilerRequestStaticState.hx'), 'utf8')
for (const requiredCall of ['EmitterStage.resetRequestState()']) {
  if (!staticOwner.includes(requiredCall)) fail(`CompilerRequestStaticState is missing ${requiredCall}`)
}
if (staticOwner.includes('SourceTargetCommon.resetRequestState()')) {
  fail('CompilerRequestStaticState must not restore the retired source-target request-reset lifecycle')
}
if (staticOwner.includes('CppTargetCore.resetRequestState()')) {
  fail('CompilerRequestStaticState must not restore the retired C++ request-reset lifecycle')
}

const stage3Compiler = fs.readFileSync(path.join(root, 'packages/hxhx/src/hxhx/Stage3Compiler.hx'), 'utf8')
for (const requiredLifecycle of [
  'registerCleanup("compiler-static-state", CompilerRequestStaticState.reset)',
  'registerCleanup("macro-state", hxhx.macro.MacroState.reset)',
  'registerCleanup("backend-plugin-state", Stage3BackendPluginSupport.resetRequestState)'
]) {
  if (!stage3Compiler.includes(requiredLifecycle)) fail(`Stage3 request lifecycle is missing ${requiredLifecycle}`)
}

const architecture = fs.readFileSync(path.join(root, 'docs/00-project/NATIVE_INCREMENTAL_SERVER_ARCHITECTURE.md'), 'utf8')
for (const requiredBoundary of [
  '## Request-state prerequisite disposition',
  '`haxe_ocaml-38gsp.1`',
  'never a reusable cache payload',
  'Macro execution remains fresh per request'
]) {
  if (!architecture.includes(requiredBoundary)) fail(`native server architecture is missing request-state boundary: ${requiredBoundary}`)
}

const total = [...observed.values()].reduce((sum, declarations) => sum + declarations.length, 0)
console.log(`[native-server-request-state-audit] OK: ${observed.size} files and ${total} process-wide declarations are individually classified`)
