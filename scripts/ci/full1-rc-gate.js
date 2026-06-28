#!/usr/bin/env node
/**
 * Full1 RC aggregate evaluator.
 *
 * This is the local and CI source of truth for the release marker. It reads the
 * Full 1.0 scope manifest, requires every planned Full1 evidence marker except
 * `FULL1_RELEASE_GO:PASS`, and emits the release marker only when all evidence
 * markers are present.
 */

const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const scopePath = path.join(root, 'docs/02-user-guide/compat/full-1.0-scope.json')
const parityMapPath = path.join(root, 'docs/00-project/PARITY_MAP_FULL_1_0.json')
const releaseMarker = 'FULL1_RELEASE_GO:PASS'

function fail(message) {
  console.error(`[full1-rc-gate] ${message}`)
  process.exit(1)
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    fail(`failed to read JSON ${path.relative(root, filePath)}: ${error.message}`)
  }
}

function usage() {
  return [
    'Usage: node scripts/ci/full1-rc-gate.js --json-out <path> --marker <MARKER>...',
    '',
    'Markers must come from successful prerequisite workflows/guards. The script',
    'prints FULL1_RELEASE_GO:PASS only when the Full1 scope evidence set is complete.'
  ].join('\n')
}

function parseArgs(argv) {
  const args = {
    jsonOut: '',
    markers: []
  }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--help' || arg === '-h') {
      console.log(usage())
      process.exit(0)
    }
    if (arg === '--json-out') {
      args.jsonOut = argv[++i] || ''
      continue
    }
    if (arg === '--marker') {
      const marker = argv[++i] || ''
      if (!marker) fail('--marker requires a value')
      args.markers.push(marker)
      continue
    }
    fail(`unknown argument: ${arg}\n${usage()}`)
  }
  if (!args.jsonOut) fail(`missing --json-out\n${usage()}`)
  return args
}

function fullScopeMarkers(scope) {
  const planned = scope && scope.full && scope.full.requiredMarkersPlanned
  if (!Array.isArray(planned) || planned.length === 0) {
    fail(`${path.relative(root, scopePath)} must define full.requiredMarkersPlanned[]`)
  }
  if (!planned.includes(releaseMarker)) {
    fail(`${path.relative(root, scopePath)} must include ${releaseMarker}`)
  }
  return planned.filter(marker => marker !== releaseMarker)
}

function validateParityMap(requiredMarkers, parityMap) {
  if (!Array.isArray(parityMap.entries) || parityMap.entries.length === 0) {
    fail(`${path.relative(root, parityMapPath)} must define entries[]`)
  }
  const entriesByMarker = new Map()
  for (const entry of parityMap.entries) {
    if (entry && entry.marker) entriesByMarker.set(entry.marker, entry)
  }
  const missingEntries = requiredMarkers.filter(marker => !entriesByMarker.has(marker))
  if (missingEntries.length > 0) {
    fail(`required Full1 markers missing from parity map: ${missingEntries.join(', ')}`)
  }
  const releaseEntry = entriesByMarker.get(releaseMarker)
  if (!releaseEntry) fail(`${path.relative(root, parityMapPath)} must include ${releaseMarker}`)
  if (releaseEntry.workflow !== '.github/workflows/gate-full1-rc.yml') {
    fail(`${releaseMarker} must be owned by .github/workflows/gate-full1-rc.yml`)
  }
}

function writeSummary(jsonOut, summary) {
  fs.mkdirSync(path.dirname(jsonOut), { recursive: true })
  fs.writeFileSync(jsonOut, `${JSON.stringify(summary, null, 2)}\n`)
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const scope = readJson(scopePath)
  const parityMap = readJson(parityMapPath)
  const requiredMarkers = fullScopeMarkers(scope)
  validateParityMap(requiredMarkers, parityMap)

  const present = new Set(args.markers)
  const missing = requiredMarkers.filter(marker => !present.has(marker))
  const summary = {
    schema: 'full1-rc-summary.v1',
    contractVersion: scope.contractVersion,
    haxeCompatibilityBaseline: scope.haxeCompatibilityBaseline,
    scopeManifest: path.relative(root, scopePath),
    parityMap: path.relative(root, parityMapPath),
    requiredMarkers,
    presentMarkers: requiredMarkers.filter(marker => present.has(marker)),
    missingMarkers: missing,
    marker: missing.length === 0 ? releaseMarker : 'FULL1_RELEASE_GO:FAIL'
  }
  writeSummary(path.resolve(args.jsonOut), summary)

  if (missing.length > 0) {
    console.error(`FULL1_RELEASE_GO:FAIL missing ${missing.length} marker(s): ${missing.join(', ')}`)
    process.exit(1)
  }

  console.log(releaseMarker)
}

main()
