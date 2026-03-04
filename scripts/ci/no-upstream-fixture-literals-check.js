#!/usr/bin/env node
/**
 * no-upstream-fixture-literals-check.js
 *
 * Guardrail for clean-room fixture provenance in compiler-core sources.
 *
 * Policy intent
 * - Stage2 parser fixtures embedded in source must be repo-owned examples.
 * - Upstream test fixture path literals/snippets must not be embedded here.
 */

const fs = require('fs')

const targetFiles = [
  'packages/hxhx-core/src/CompilerDriver.hx',
  'packages/hxhx-core/src/FrontendFixture.hx',
]

const forbiddenPatterns = [
  { label: 'upstream tests/misc fixture path literal', re: /tests\/misc\// },
  { label: 'upstream tests/unit fixture path literal', re: /tests\/unit\// },
  { label: 'upstream tests/runci fixture path literal', re: /tests\/runci\// },
  { label: 'vendor/haxe test fixture path literal', re: /vendor\/haxe\/tests\// },
  { label: 'stale upstream-shaped fixture wording', re: /upstream-shaped/ },
]

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function readUtf8(path) {
  return fs.readFileSync(path, 'utf8')
}

function main() {
  for (const file of targetFiles) {
    let text = ''
    try {
      text = readUtf8(file)
    } catch (error) {
      fail(`failed to read ${file}: ${error.message}`)
      continue
    }
    const lines = text.split(/\r?\n/)
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i]
      for (const pattern of forbiddenPatterns) {
        if (pattern.re.test(line)) {
          fail(`${file}:${i + 1} contains forbidden fixture provenance pattern (${pattern.label})`)
        }
      }
    }
  }

  if (!process.exitCode) {
    console.log('[ci:guards] OK: no upstream fixture literals in Stage2 embedded parser fixtures')
  }
}

main()
