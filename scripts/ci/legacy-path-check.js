#!/usr/bin/env node
/**
 * legacy-path-check.js
 *
 * Guardrail for repository path migrations:
 * - forbid reintroducing old internal paths after the hxhx-first move.
 *
 * Scope rules:
 * - scan tracked text files only;
 * - exclude generated/bootstrap snapshots and other metadata trees.
 */

const fs = require('fs')
const cp = require('child_process')

const forbiddenPatterns = [
  /packages\/hih-compiler/g,
  /\.\.\/hih-compiler/g,
  /tools\/hxhx-macro-host/g,
]

const excludedPrefixes = [
  '.beads/',
  'vendor/',
  'packages/hxhx/bootstrap_out/',
  'packages/hxhx-macro-host/bootstrap_out/',
  'test/snapshot/',
]

function gitTrackedAll() {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function shouldSkipPath(path) {
  return excludedPrefixes.some(prefix => path.startsWith(prefix))
}

function shouldScanText(path) {
  if (shouldSkipPath(path)) {
    return false
  }
  const lower = path.toLowerCase()
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.ico')) return false
  if (lower.endsWith('.pdf') || lower.endsWith('.zip') || lower.endsWith('.gz') || lower.endsWith('.tar') || lower.endsWith('.tgz')) return false
  if (lower.endsWith('.exe') || lower.endsWith('.bc') || lower.endsWith('.a') || lower.endsWith('.so') || lower.endsWith('.dylib')) return false
  return true
}

function main() {
  const violations = []
  for (const path of gitTrackedAll()) {
    if (!shouldScanText(path)) continue
    let text = ''
    try {
      text = fs.readFileSync(path, 'utf8')
    } catch (_) {
      continue
    }
    for (const pattern of forbiddenPatterns) {
      pattern.lastIndex = 0
      if (pattern.test(text)) {
        violations.push(`${path} (matched ${pattern})`)
      }
    }
  }

  if (violations.length > 0) {
    console.error('[ci:guards] ERROR: legacy path references found:\n- ' + violations.join('\n- '))
    process.exit(1)
  }

  console.log('[ci:guards] OK: no forbidden legacy paths found')
}

main()
