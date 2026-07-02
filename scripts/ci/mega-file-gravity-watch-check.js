#!/usr/bin/env node
/**
 * Guard the mega-file gravity watch.
 *
 * This check keeps the architecture note current enough to be useful without
 * turning line counts into hard budgets. It allows small drift so routine
 * bounded fixes do not have to update the table on every patch.
 */

const fs = require('fs')

const docPath = 'docs/00-project/MEGA_FILE_GRAVITY_WATCH.md'
const docsReadmePath = 'docs/README.md'
const northStarPath = 'docs/00-project/NORTH_STAR_GOALS.md'
const packageJsonPath = 'package.json'
const maxLineDrift = 250

const watchedFiles = [
  'packages/hxhx-core/src/backend/source/SourceTargetCommon.hx',
  'packages/hxhx-core/src/backend/cpp/CppTargetCore.hx',
  'packages/hxhx-core/src/EmitterStage.hx',
  'packages/hxhx-core/src/HxParser.hx',
  'packages/hxhx-core/src/ParserStage.hx',
  'packages/hxhx/src/hxhx/Stage3Compiler.hx',
]

function fail(message) {
  console.error(`[mega-file-gravity-watch-check] ERROR: ${message}`)
  process.exitCode = 1
}

function readText(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`missing required file: ${filePath}`)
    return ''
  }
  return fs.readFileSync(filePath, 'utf8')
}

function requireIncludes(filePath, text, snippet) {
  if (!text.includes(snippet)) {
    fail(`${filePath} must include: ${snippet}`)
  }
}

function lineCount(filePath) {
  const text = readText(filePath)
  const matches = text.match(/\n/g)
  return matches ? matches.length : 0
}

function documentedLineCount(doc, filePath) {
  const escapedPath = filePath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const pattern = new RegExp(`\\| \`${escapedPath}\` \\| ([0-9,]+) \\|`)
  const match = doc.match(pattern)
  if (!match) {
    fail(`${docPath} must include a Current Hotspots row for ${filePath}`)
    return null
  }
  return Number(match[1].replace(/,/g, ''))
}

function main() {
  const doc = readText(docPath)
  const docsReadme = readText(docsReadmePath)
  const northStar = readText(northStarPath)
  const packageJson = readText(packageJsonPath)

  for (const snippet of [
    'MEGA_FILE_GRAVITY_WATCH:PASS',
    'haxe_ocaml-zn07',
    'haxe_ocaml-8b0o',
    'README and North Star progress bars stay unchanged by default',
    'red',
    'orange',
    'yellow',
    'Bounded Fix Rule',
    'Existing Follow-Ups',
    'npm run guard:mega-file-gravity-watch',
  ]) {
    requireIncludes(docPath, doc, snippet)
  }

  for (const filePath of watchedFiles) {
    const documented = documentedLineCount(doc, filePath)
    const actual = lineCount(filePath)
    if (documented == null)
      continue
    const drift = Math.abs(actual - documented)
    if (drift > maxLineDrift) {
      fail(`${docPath} line count for ${filePath} is stale: documented ${documented}, actual ${actual}, drift ${drift}`)
    }
  }

  requireIncludes(docsReadmePath, docsReadme, 'MEGA_FILE_GRAVITY_WATCH.md')
  requireIncludes(northStarPath, northStar, 'MEGA_FILE_GRAVITY_WATCH.md')
  requireIncludes(packageJsonPath, packageJson, 'guard:mega-file-gravity-watch')
  requireIncludes(packageJsonPath, packageJson, 'mega-file-gravity-watch-check.js')

  if (process.exitCode) return
  console.log('[ci:guards] OK: mega-file gravity watch is current enough')
  console.log('MEGA_FILE_GRAVITY_WATCH:PASS')
}

main()
