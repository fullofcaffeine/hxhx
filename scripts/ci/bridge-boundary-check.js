#!/usr/bin/env node
/**
 * Keep temporary native/bootstrap adapters inside their documented files.
 *
 * The companion document explains the user-facing reason for each bridge:
 * docs/00-project/BOOTSTRAP_BRIDGE_RETIREMENT.md
 */

const cp = require('child_process')
const fs = require('fs')

const manifestPath = 'docs/00-project/BOOTSTRAP_BRIDGE_INVENTORY.json'
const genIrProgramPath = 'packages/hxhx-core/src/backend/GenIrProgram.hx'
const backendDispatchPath = 'packages/hxhx-core/src/backend/BackendDispatchBoundary.hx'
const compilerDriverPath = 'packages/hxhx-core/src/CompilerDriver.hx'
const nativeCompilerServerPath = 'packages/hxhx/src/hxhx/NativeCompilerServer.hx'

const expectedAllowedFiles = {
  'backend-dispatch-reflection': [
    backendDispatchPath,
    'packages/hxhx/src/hxhx/Stage3EmitSupport.hx',
  ],
  'genir-dynamic-recovery': [
    'packages/hxhx-core/src/backend/GenIrBoundary.hx',
    'packages/hxhx/src/hxhx/Stage3EmitSupport.hx',
    'packages/hxhx-core/src/backend/js/JsTargetCore.hx',
    'packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx',
  ],
  'compiler-driver-ocaml-hint': [compilerDriverPath],
  'compiler-server-socket-helper': [
    nativeCompilerServerPath,
    'packages/hxhx/src/hxhx/Stage3WaitServer.hx',
  ],
}

const occurrenceRules = [
  {
    label: 'BackendDispatchBoundary.emit call',
    pattern: /\bBackendDispatchBoundary\.emit\s*\(/g,
    expected: {'packages/hxhx/src/hxhx/Stage3EmitSupport.hx': 1},
  },
  {
    label: 'external BackendDispatchBoundary.emitReflective call',
    pattern: /\bBackendDispatchBoundary\.emitReflective\s*\(/g,
    expected: {},
  },
  {
    label: 'reflective emit lookup',
    pattern: /\bReflect\.field\s*\([^,\n]+,\s*["']emit["']\s*\)/g,
    expected: {[backendDispatchPath]: 1},
  },
  {
    label: 'reflective emit invocation',
    pattern: /\bReflect\.callMethod\s*\(\s*backend\s*,\s*emitFn\b/g,
    expected: {[backendDispatchPath]: 1},
  },
  {
    label: 'GenIrBoundary.fromDynamic call',
    pattern: /\bGenIrBoundary\.fromDynamic\s*\(/g,
    expected: {'packages/hxhx/src/hxhx/Stage3EmitSupport.hx': 1},
  },
  {
    label: 'GenIrBoundary.requireProgram call',
    pattern: /\bGenIrBoundary\.requireProgram\s*\(/g,
    expected: {
      'packages/hxhx-core/src/backend/js/JsTargetCore.hx': 1,
      'packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx': 1,
    },
  },
  {
    label: 'GenIrBoundary.asBackendProgram call',
    pattern: /\bGenIrBoundary\.asBackendProgram\s*\(/g,
    expected: {},
  },
  {
    label: 'compiler source untyped __ocaml__ call',
    pattern: /\buntyped\s+__ocaml__\s*\(/g,
    expected: {[compilerDriverPath]: 1},
  },
  {
    label: 'NativeCompilerServer.waitSocket call',
    pattern: /\bNativeCompilerServer\.waitSocket\s*\(/g,
    expected: {'packages/hxhx/src/hxhx/Stage3WaitServer.hx': 1},
  },
  {
    label: 'NativeCompilerServer.connect call',
    pattern: /\bNativeCompilerServer\.connect\s*\(/g,
    expected: {'packages/hxhx/src/hxhx/Stage3WaitServer.hx': 1},
  },
  {
    label: 'HxHxCompilerServer native binding',
    pattern: /@:native\s*\(\s*["']HxHxCompilerServer["']\s*\)/g,
    expected: {[nativeCompilerServerPath]: 1},
  },
  {
    label: 'direct sys.net.Socket use in current compiler source',
    pattern: /\bsys\.net\.Socket\b/g,
    expected: {},
  },
]

function listSourceFiles() {
  const output = cp.execFileSync(
    'git',
    ['ls-files', '-co', '--exclude-standard', '-z', 'packages/hxhx-core/src', 'packages/hxhx/src/hxhx'],
    {encoding: 'utf8'}
  )
  return output
    .split('\0')
    .filter(path => path.endsWith('.hx'))
    .sort()
}

/**
 * Remove comments while preserving string contents.
 *
 * Preserving strings matters because raw target escapes are real source calls,
 * while examples in HaxeDoc comments must not be counted as call sites.
 */
function stripComments(source) {
  let output = ''
  let index = 0
  let state = 'code'
  let quote = ''

  while (index < source.length) {
    const current = source[index]
    const next = source[index + 1]

    if (state === 'line-comment') {
      if (current === '\n') {
        output += '\n'
        state = 'code'
      } else {
        output += ' '
      }
      index++
      continue
    }

    if (state === 'block-comment') {
      if (current === '*' && next === '/') {
        output += '  '
        index += 2
        state = 'code'
      } else {
        output += current === '\n' ? '\n' : ' '
        index++
      }
      continue
    }

    if (state === 'string') {
      output += current
      if (current === '\\' && index + 1 < source.length) {
        output += source[index + 1]
        index += 2
        continue
      }
      if (current === quote) state = 'code'
      index++
      continue
    }

    if (current === '/' && next === '/') {
      output += '  '
      index += 2
      state = 'line-comment'
      continue
    }
    if (current === '/' && next === '*') {
      output += '  '
      index += 2
      state = 'block-comment'
      continue
    }
    if (current === '"' || current === "'") {
      quote = current
      state = 'string'
    }
    output += current
    index++
  }

  return output
}

function readSourceMap() {
  const sources = new Map()
  for (const path of listSourceFiles()) {
    sources.set(path, stripComments(fs.readFileSync(path, 'utf8')))
  }
  return sources
}

function readManifest() {
  return JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
}

function sortedUnique(values) {
  return [...new Set(values)].sort()
}

function sameStrings(left, right) {
  return JSON.stringify(sortedUnique(left)) === JSON.stringify(sortedUnique(right))
}

function countMatches(source, pattern) {
  const copy = new RegExp(pattern.source, pattern.flags)
  return (source.match(copy) || []).length
}

function validateManifest(manifest, sources, exists = fs.existsSync) {
  const errors = []
  if (manifest.schema !== 'hxhx.bootstrap-bridge-inventory.v1') {
    errors.push(`unexpected bridge inventory schema: ${String(manifest.schema)}`)
  }
  if (manifest.marker !== 'BRIDGE_RETIREMENT_INVENTORY:PASS') {
    errors.push(`unexpected bridge inventory marker: ${String(manifest.marker)}`)
  }
  if (!Array.isArray(manifest.bridges)) {
    errors.push('bridge inventory must contain a bridges array')
    return errors
  }

  const expectedIds = Object.keys(expectedAllowedFiles).sort()
  const actualIds = manifest.bridges.map(bridge => bridge && bridge.id).filter(Boolean)
  if (!sameStrings(actualIds, expectedIds) || actualIds.length !== expectedIds.length) {
    errors.push(`bridge ids must be exactly: ${expectedIds.join(', ')}`)
  }

  for (const bridge of manifest.bridges) {
    if (!bridge || typeof bridge !== 'object') {
      errors.push('each bridge entry must be an object')
      continue
    }
    const label = bridge.id || '<missing id>'
    for (const field of ['plainName', 'reason']) {
      if (typeof bridge[field] !== 'string' || bridge[field].trim().length === 0) {
        errors.push(`${label}.${field} must be a non-empty string`)
      }
    }
    for (const field of ['ownerBeads', 'allowedHaxeFiles', 'focusedRegressions', 'exitEvidence']) {
      if (!Array.isArray(bridge[field]) || bridge[field].length === 0) {
        errors.push(`${label}.${field} must be a non-empty array`)
      }
    }

    const expected = expectedAllowedFiles[bridge.id]
    if (expected && !sameStrings(bridge.allowedHaxeFiles || [], expected)) {
      errors.push(`${label}.allowedHaxeFiles must be exactly: ${expected.join(', ')}`)
    }
    for (const path of bridge.allowedHaxeFiles || []) {
      if (!sources.has(path)) errors.push(`${label} allowed Haxe file is missing from source scope: ${path}`)
    }
    for (const path of bridge.runtimeSourceFiles || []) {
      if (!exists(path)) errors.push(`${label} runtime source file does not exist: ${path}`)
    }
  }
  return errors
}

function validateOccurrences(sources) {
  const errors = []
  for (const rule of occurrenceRules) {
    for (const [path, source] of sources) {
      const actual = countMatches(source, rule.pattern)
      const expected = rule.expected[path] || 0
      if (actual !== expected) {
        errors.push(`${rule.label}: expected ${expected} in ${path}, found ${actual}`)
      }
    }
    for (const [path, expected] of Object.entries(rule.expected)) {
      if (!sources.has(path)) errors.push(`${rule.label}: expected source file is missing: ${path} (${expected} call expected)`)
    }
  }
  return errors
}

function validateSourceContracts(sources) {
  const errors = []
  const genIrProgram = sources.get(genIrProgramPath) || ''
  if (countMatches(genIrProgram, /\btypedef\s+GenIrProgram\s*=\s*MacroExpandedProgram\s*;/g) !== 1) {
    errors.push('GenIrProgram must remain one explicit MacroExpandedProgram boundary alias')
  }
  const rawGenIrSource = fs.existsSync(genIrProgramPath) ? fs.readFileSync(genIrProgramPath, 'utf8') : ''
  if (!/not a normalized or target-neutral IR/i.test(rawGenIrSource)) {
    errors.push('GenIrProgram documentation must say that it is not a normalized or target-neutral IR')
  }

  const compilerDriver = sources.get(compilerDriverPath) || ''
  if (countMatches(compilerDriver, /\buntyped\s+__ocaml__\s*\(\s*["']\(ResolvedModule\.getParsed\)["']\s*\)/g) !== 1) {
    errors.push('CompilerDriver must contain exactly the approved zero-cost ResolvedModule.getParsed OCaml hint')
  }
  return errors
}

function validateRepositoryState(sources, manifest, exists = fs.existsSync) {
  return [
    ...validateManifest(manifest, sources, exists),
    ...validateOccurrences(sources),
    ...validateSourceContracts(sources),
  ]
}

function main() {
  const sources = readSourceMap()
  const manifest = readManifest()
  const errors = validateRepositoryState(sources, manifest)
  if (errors.length > 0) {
    console.error('[ci:guards] ERROR: temporary bridge boundary drift detected:')
    for (const error of errors) console.error(`- ${error}`)
    process.exit(1)
  }
  console.log('[ci:guards] OK: BRIDGE_RETIREMENT_INVENTORY:PASS')
}

if (require.main === module) main()

module.exports = {
  readManifest,
  readSourceMap,
  stripComments,
  validateRepositoryState,
}
