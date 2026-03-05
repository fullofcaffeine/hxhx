#!/usr/bin/env node
/**
 * no-legacy-target-docs-check.js
 *
 * Guardrail for hard CLI cutover:
 * - `--target` / `--hxhx-target` are removed compile-lane flags.
 * - Docs may mention removal, but must not teach legacy compile usage.
 * - Plugin tooling flags (`--target-id`, `--target-name`, `--target-namespace`) stay valid.
 */

const fs = require('fs')
const cp = require('child_process')

const allowedRemovalPatterns = [
  /\b--target\b\s+was\s+removed\b/i,
  /\b--target\b\s+removed\b/i,
  /Removed flags:\s*`?--target\b/i,
  /`--target`\s+is\s+removed\b/i,
]

function gitTrackedAll() {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function shouldScan(path) {
  if (path === 'README.md' || path === 'AGENTS.md') return true
  if (path.startsWith('docs/') && path.endsWith('.md')) return true
  if (path.startsWith('packages/') && path.endsWith('/README.md')) return true
  if (path.startsWith('test/') && path.endsWith('/README.md')) return true
  if (path.startsWith('examples/') && path.endsWith('/README.md')) return true
  return false
}

function isAllowedLine(line) {
  if (line.includes('--target-id') || line.includes('--target-name') || line.includes('--target-namespace')) {
    return true
  }
  return allowedRemovalPatterns.some((re) => re.test(line))
}

function main() {
  const violations = []
  for (const path of gitTrackedAll()) {
    if (!shouldScan(path)) continue

    let text = ''
    try {
      text = fs.readFileSync(path, 'utf8')
    } catch (_) {
      continue
    }

    const lines = text.split(/\r?\n/)
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i]
      if (!/\b--target(\s+|=)/.test(line)) continue
      if (isAllowedLine(line)) continue
      violations.push(`${path}:${i + 1}: ${line.trim()}`)
    }
  }

  if (violations.length > 0) {
    console.error('[ci:guards] ERROR: legacy --target compile guidance found:')
    for (const v of violations) {
      console.error(`- ${v}`)
    }
    process.exit(1)
  }

  console.log('[ci:guards] OK: no legacy --target compile guidance in docs')
}

main()
