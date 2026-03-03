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
  'packages/hxhx-core/src/backend/plugin/BackendPluginManifestParser.hx',
  'packages/hxhx-core/src/backend/plugin/ManifestJsonParser.hx',
  'packages/hxhx-core/src/backend/plugin/ManifestJsonArray.hx',
  'packages/hxhx-core/src/backend/BackendDispatchBoundary.hx',
  'packages/hxhx-core/src/backend/GenIrBoundary.hx',
  'packages/hxhx/src/hxhx/Stage3Compiler.hx',
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

function isCommentLine(line) {
  const trimmed = line.trim()
  return (
    trimmed.startsWith('//') ||
    trimmed.startsWith('/*') ||
    trimmed.startsWith('*') ||
    trimmed.startsWith('*/')
  )
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

    const lines = text.split('\n')
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index]
      if (isCommentLine(line)) continue
      for (const pattern of patterns) {
        if (pattern.re.test(line)) {
          violations.push(`${path}:${index + 1} [${pattern.label}] ${line.trim()}`)
          break
        }
      }
    }
  }

  if (violations.length > 0) {
    fail(
      'Dynamic/Any/untyped policy violation outside allowlist:\n- ' +
      violations.slice(0, 60).join('\n- ')
    )
  }

  console.log('[ci:guards] OK: Dynamic/untyped usage stays within allowlisted boundaries')
}

main()
