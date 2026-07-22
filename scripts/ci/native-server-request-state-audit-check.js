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

if (audit.schema !== 'hxhx-native-server-request-state-audit.v2') fail('unsupported or missing audit schema')
if (!Array.isArray(audit.scope) || audit.scope.length === 0) fail('audit scope must list source directories')
if (!Array.isArray(audit.entries) || audit.entries.length === 0) fail('audit entries must not be empty')

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

const staticOwner = fs.readFileSync(path.join(root, 'packages/hxhx-core/src/CompilerRequestStaticState.hx'), 'utf8')
for (const requiredCall of [
  'HxParser.resetRequestState()',
  'EmitterStage.resetRequestState()',
  'CppTargetCore.resetRequestState()',
  'SourceTargetCommon.resetRequestState()'
]) {
  if (!staticOwner.includes(requiredCall)) fail(`CompilerRequestStaticState is missing ${requiredCall}`)
}

const stage3Compiler = fs.readFileSync(path.join(root, 'packages/hxhx/src/hxhx/Stage3Compiler.hx'), 'utf8')
for (const requiredLifecycle of [
  'registerCleanup("compiler-static-state", CompilerRequestStaticState.reset)',
  'registerCleanup("macro-state", hxhx.macro.MacroState.reset)',
  'registerCleanup("backend-plugin-state", Stage3BackendPluginSupport.resetRequestState)'
]) {
  if (!stage3Compiler.includes(requiredLifecycle)) fail(`Stage3 request lifecycle is missing ${requiredLifecycle}`)
}

const total = [...observed.values()].reduce((sum, declarations) => sum + declarations.length, 0)
console.log(`[native-server-request-state-audit] OK: ${observed.size} files and ${total} process-wide declarations are individually classified`)
