#!/usr/bin/env node
/**
 * no-dynamic-check.js
 *
 * Guardrail for Dynamic/Any/untyped usage in hxhx compiler lanes.
 *
 * Policy
 * - Dynamic/Any/untyped are forbidden by default.
 * - Allow only explicit runtime boundary files (JSON/protocol/dispatch seams).
 * - Keep allowlists narrowly scoped to true runtime boundaries.
 */

const fs = require('fs')
const cp = require('child_process')

const scopePrefixes = [
  'packages/hxhx-core/src/backend/',
  'packages/hxhx-core/src/hxhx/',
  'packages/hxhx-core/src/hxhxmacrohost/',
  'packages/hxhx/src/hxhx/',
  'packages/hxhx-macro-host/src/hxhxmacrohost/',
]

const scopedSingleFiles = [
  'packages/hxhx-core/src/EmitterStage.hx',
]

const boundaryPrefixAllowlist = [
  'packages/hxhx-macro-host/src/hxhxmacrohost/',
]

const boundaryFileAllowlist = new Set([
  'packages/hxhx-core/src/backend/BackendDispatchBoundary.hx',
  'packages/hxhx-core/src/backend/GenIrBoundary.hx',
  'packages/hxhx/src/hxhx/Stage3Compiler.hx',
  'packages/hxhx/src/hxhx/Stage3DiagnosticsSupport.hx',
  'packages/hxhx/src/hxhx/BackendPluginManifestResolver.hx',
])

const temporaryAllowlist = new Set([])

const patterns = [
  { label: 'typed_dynamic', re: /:\s*Dynamic\b/ },
  { label: 'generic_dynamic', re: /<Dynamic>/ },
  { label: 'typed_any', re: /:\s*(?:Std\.)?Any\b/ },
  { label: 'generic_any', re: /<\s*(?:Std\.)?Any\s*>/ },
  { label: 'catch_dynamic', re: /\bcatch\s*\([^)]*:\s*Dynamic\)/ },
  { label: 'untyped_ocaml', re: /\buntyped\s+__ocaml__/ },
]

function gitTrackedAll() {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function inScope(path) {
  if (!path.endsWith('.hx')) return false
  if (scopedSingleFiles.includes(path)) return true
  return scopePrefixes.some(prefix => path.startsWith(prefix))
}

/**
 * Hide literal data and comments while retaining executable interpolation.
 * Spaces preserve source offsets and newlines preserve diagnostic line numbers.
 * This is lexical masking for the policy patterns, not a Haxe type checker.
 */
function executableText(source) {
  const output = source.split('')
  let index = 0
  function hide() {
    if (source[index] !== '\n' && source[index] !== '\r') output[index] = ' '
    index++
  }
  function literal(quote, regex = false) {
    hide()
    let characterClass = false
    while (index < source.length) {
      const current = source[index]
      if (current === '\\') {
        hide()
        if (index < source.length) hide()
      } else if (quote === "'" && current === '$' && source[index + 1] === '$') {
        hide()
        hide()
      } else if (quote === "'" && current === '$' && source[index + 1] === '{') {
        hide()
        hide()
        code(true)
      } else if (current === quote && !characterClass) {
        hide()
        return
      } else {
        if (regex && current === '[') characterClass = true
        if (regex && current === ']') characterClass = false
        hide()
      }
    }
  }
  function code(interpolation = false) {
    let depth = 1
    while (index < source.length) {
      const current = source[index]
      const next = source[index + 1]
      if (current === '/' && next === '/') {
        while (index < source.length && source[index] !== '\n') hide()
      } else if (current === '/' && next === '*') {
        hide()
        hide()
        while (index < source.length && !(source[index] === '*' && source[index + 1] === '/')) hide()
        if (index < source.length) { hide(); hide() }
      } else if (current === '~' && next === '/') {
        hide()
        literal('/', true)
      } else if (current === '"' || current === "'") {
        literal(current)
      } else if (interpolation && current === '}' && --depth === 0) {
        hide()
        return
      } else {
        if (interpolation && current === '{') depth++
        index++
      }
    }
  }
  code()
  return output.join('')
}

function isAllowed(path) {
  if (temporaryAllowlist.has(path)) return true
  if (boundaryFileAllowlist.has(path)) return true
  return boundaryPrefixAllowlist.some(prefix => path.startsWith(prefix))
}

function fail(msg) {
  console.error(`[ci:guards] ERROR: ${msg}`)
  process.exit(1)
}

/** Returns policy matches with their original source lines. */
function violationsInText(path, text) {
  const violations = []
  const lines = text.split('\n')
  const codeLines = executableText(text).split('\n')
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]
    for (const pattern of patterns) {
      if (pattern.re.test(codeLines[index])) {
        violations.push({path, line: index + 1, label: pattern.label, source: line.trim()})
        break
      }
    }
  }
  return violations
}

function main() {
  const violations = []
  for (const path of gitTrackedAll()) {
    if (!inScope(path)) continue
    if (isAllowed(path)) continue

    let text
    try {
      text = fs.readFileSync(path, 'utf8')
    } catch (_) {
      continue
    }

    violations.push(...violationsInText(path, text).map(value =>
      `${value.path}:${value.line} [${value.label}] ${value.source}`))
  }

  if (violations.length > 0) {
    fail(
      'Dynamic/Any/untyped policy violation outside allowlist:\n- ' +
      violations.slice(0, 60).join('\n- ')
    )
  }

  console.log('[ci:guards] OK: Dynamic/untyped usage stays within allowlisted boundaries')
}

if (require.main === module) main()
module.exports = {violationsInText}
