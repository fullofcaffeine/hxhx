#!/usr/bin/env node
/**
 * full1-parity-map-check.js
 *
 * Guardrail for Full 1.0 parity map integrity:
 * - map files must exist and parse,
 * - marker registry must be unique,
 * - required-now suites must be covered,
 * - required-now markers must map to existing workflow files.
 */

const fs = require('fs')

const mapDocPath = 'docs/00-project/PARITY_MAP_FULL_1_0.md'
const mapJsonPath = 'docs/00-project/PARITY_MAP_FULL_1_0.json'
const ciGatesDocPath = 'docs/00-project/CI_GATES.md'
const contractDocPath = 'docs/00-project/FULL_1_0_CONTRACT.md'

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function exists(path) {
  return fs.existsSync(path)
}

function readUtf8(path) {
  return fs.readFileSync(path, 'utf8')
}

function requirePath(path) {
  if (!exists(path)) {
    fail(`missing required path: ${path}`)
    return false
  }
  return true
}

function markerPrefix(marker) {
  return String(marker).split(':')[0]
}

function main() {
  if (!requirePath(mapDocPath)) return
  if (!requirePath(mapJsonPath)) return
  if (!requirePath(ciGatesDocPath)) return
  if (!requirePath(contractDocPath)) return

  const ciGatesDoc = readUtf8(ciGatesDocPath)
  if (!ciGatesDoc.includes(mapDocPath)) {
    fail(`CI gates doc must reference ${mapDocPath}`)
  }

  const contractDoc = readUtf8(contractDocPath)
  if (!contractDoc.includes(mapJsonPath) && !contractDoc.includes(mapDocPath)) {
    fail(`Full 1.0 contract doc must reference ${mapJsonPath} or ${mapDocPath}`)
  }

  let parityMap = null
  try {
    parityMap = JSON.parse(readUtf8(mapJsonPath))
  } catch (error) {
    fail(`invalid JSON in ${mapJsonPath}: ${error.message}`)
    return
  }

  if (parityMap.haxeCompatibilityBaseline !== '4.3.7') {
    fail(`parity map baseline must be 4.3.7 (received: ${parityMap.haxeCompatibilityBaseline})`)
  }
  if (!Array.isArray(parityMap.requiredNowSuites) || parityMap.requiredNowSuites.length === 0) {
    fail('parity map must define requiredNowSuites[]')
  }
  if (!Array.isArray(parityMap.entries) || parityMap.entries.length === 0) {
    fail('parity map must define entries[]')
    return
  }

  const markerSeen = new Set()
  const requiredNowSuiteCoverage = new Map()
  for (const suite of parityMap.requiredNowSuites) {
    requiredNowSuiteCoverage.set(suite, 0)
  }

  for (const entry of parityMap.entries) {
    const requiredFields = ['id', 'suite', 'lane', 'targets', 'profile', 'marker', 'workflow', 'enforcement']
    for (const field of requiredFields) {
      if (entry[field] === undefined || entry[field] === null || entry[field] === '') {
        fail(`parity entry missing required field "${field}": ${JSON.stringify(entry)}`)
      }
    }
    if (!Array.isArray(entry.targets) || entry.targets.length === 0) {
      fail(`parity entry ${entry.id} must define non-empty targets[]`)
    }

    if (markerSeen.has(entry.marker)) {
      fail(`duplicate marker in parity map: ${entry.marker}`)
    } else {
      markerSeen.add(entry.marker)
    }

    if (entry.enforcement !== 'required_now' && entry.enforcement !== 'planned') {
      fail(`entry ${entry.id} has invalid enforcement "${entry.enforcement}"`)
      continue
    }

    if (entry.enforcement === 'required_now') {
      if (requiredNowSuiteCoverage.has(entry.suite)) {
        requiredNowSuiteCoverage.set(entry.suite, requiredNowSuiteCoverage.get(entry.suite) + 1)
      }

      if (!exists(entry.workflow)) {
        fail(`required_now entry ${entry.id} references missing workflow ${entry.workflow}`)
        continue
      }

      const workflowText = readUtf8(entry.workflow)
      if (!workflowText.includes(entry.marker) && !workflowText.includes(markerPrefix(entry.marker))) {
        fail(`required_now marker ${entry.marker} is not discoverable in ${entry.workflow}`)
      }
    }
  }

  for (const [suite, count] of requiredNowSuiteCoverage.entries()) {
    if (count <= 0) {
      fail(`requiredNowSuites entry has no required_now parity map row: ${suite}`)
    }
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full 1.0 parity map is valid')
  console.log('FULL1_PARITY_MAP:PASS')
}

main()
