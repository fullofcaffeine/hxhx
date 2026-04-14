#!/usr/bin/env node
/**
 * Guard the Full1 performance parity policy contract.
 *
 * This check validates the policy document and emits the contract marker. It
 * does not execute performance workloads or claim measured parity.
 */

const fs = require('fs')

const policyDocPath = 'docs/00-project/FULL1_PERF_PARITY_POLICY.md'
const fullContractPath = 'docs/00-project/FULL_1_0_CONTRACT.md'
const scopeManifestPath = 'docs/02-user-guide/compat/full-1.0-scope.json'
const parityMapDocPath = 'docs/00-project/PARITY_MAP_HAXE_4_3_7.md'
const parityMapJsonPath = 'docs/00-project/PARITY_MAP_FULL_1_0.json'
const ciGatesDocPath = 'docs/00-project/CI_GATES.md'
const packageJsonPath = 'package.json'

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exitCode = 1
}

function readUtf8(path) {
  if (!fs.existsSync(path)) {
    fail(`missing required file: ${path}`)
    return ''
  }
  return fs.readFileSync(path, 'utf8')
}

function readJson(path) {
  const text = readUtf8(path)
  if (!text) return null
  try {
    return JSON.parse(text)
  } catch (error) {
    fail(`invalid JSON in ${path}: ${error.message}`)
    return null
  }
}

function requireIncludes(path, text, snippet) {
  if (!text.includes(snippet)) fail(`${path} must include: ${snippet}`)
}

function extractPolicyJson(doc) {
  const match = doc.match(
    /<!-- FULL1_PERF_POLICY_JSON_START -->\s*```json\s*([\s\S]*?)\s*```\s*<!-- FULL1_PERF_POLICY_JSON_END -->/
  )
  if (!match) {
    fail(`${policyDocPath} must include a fenced JSON block between FULL1_PERF_POLICY_JSON_START/END markers`)
    return null
  }
  try {
    return JSON.parse(match[1])
  } catch (error) {
    fail(`${policyDocPath} policy JSON is invalid: ${error.message}`)
    return null
  }
}

function requirePositiveNumber(object, field, owner) {
  if (typeof object[field] !== 'number' || object[field] <= 0) {
    fail(`${owner}.${field} must be a positive number`)
  }
}

function checkWorkload(workload, packageScripts) {
  const owner = `workload ${workload && workload.id ? workload.id : '<missing-id>'}`
  for (const field of ['id', 'npmScript', 'source']) {
    if (!workload || typeof workload[field] !== 'string' || workload[field] === '') {
      fail(`${owner} must define non-empty ${field}`)
    }
  }
  if (!Array.isArray(workload.requiredMetrics) || workload.requiredMetrics.length === 0) {
    fail(`${owner} must define requiredMetrics[]`)
  }
  if (workload.source && !fs.existsSync(workload.source)) {
    fail(`${owner} references missing source file: ${workload.source}`)
  }
  if (workload.workflow && !fs.existsSync(workload.workflow)) {
    fail(`${owner} references missing workflow: ${workload.workflow}`)
  }
  if (workload.npmScript && !packageScripts[workload.npmScript]) {
    fail(`${owner} references missing package.json script: ${workload.npmScript}`)
  }
}

function main() {
  const policyDoc = readUtf8(policyDocPath)
  const fullContract = readUtf8(fullContractPath)
  const scopeManifestText = readUtf8(scopeManifestPath)
  const parityMapDoc = readUtf8(parityMapDocPath)
  const parityMapJson = readJson(parityMapJsonPath)
  const ciGatesDoc = readUtf8(ciGatesDocPath)
  const packageJson = readJson(packageJsonPath)

  for (const snippet of [
    'FULL1_PERF_POLICY:PASS',
    'FULL1_PERF_PARITY:PASS',
    'Haxe 4.3.7',
    'stage0-free hxhx',
    'scripts/ci/full1-perf-policy-check.js',
    'npm run hxhx:bench:kpi',
    'npm run test:full1:eval-native',
    'npm run test:full1:suites:strict',
    '.github/workflows/hxhx-kpi-report.yml'
  ]) {
    requireIncludes(policyDocPath, policyDoc, snippet)
  }

  requireIncludes(fullContractPath, fullContract, policyDocPath)
  requireIncludes(fullContractPath, fullContract, 'FULL1_PERF_POLICY:PASS')
  requireIncludes(fullContractPath, fullContract, 'FULL1_PERF_PARITY:PASS')
  requireIncludes(scopeManifestPath, scopeManifestText, 'FULL1_PERF_POLICY:PASS')
  requireIncludes(scopeManifestPath, scopeManifestText, 'FULL1_PERF_PARITY:PASS')
  requireIncludes(parityMapDocPath, parityMapDoc, 'FULL1_PERF_POLICY:PASS')
  requireIncludes(parityMapDocPath, parityMapDoc, 'FULL1_PERF_PARITY:PASS')
  requireIncludes(ciGatesDocPath, ciGatesDoc, 'FULL1_PERF_POLICY:PASS')

  const policy = extractPolicyJson(policyDoc)
  if (!policy) return

  if (policy.schema !== 'full1-perf-policy.v1') fail(`unexpected policy schema: ${policy.schema}`)
  if (policy.haxeCompatibilityBaseline !== '4.3.7') {
    fail(`policy baseline must be 4.3.7 (received: ${policy.haxeCompatibilityBaseline})`)
  }
  if (policy.contractMarker !== 'FULL1_PERF_POLICY:PASS') fail(`unexpected contract marker: ${policy.contractMarker}`)
  if (policy.evidenceMarker !== 'FULL1_PERF_PARITY:PASS') fail(`unexpected evidence marker: ${policy.evidenceMarker}`)
  if (policy.releaseBlocking !== true) fail('policy.releaseBlocking must be true')
  if (policy.stage0MaintenanceOnly !== true) fail('policy.stage0MaintenanceOnly must be true')
  if (policy.runtimeLane !== 'stage0-free hxhx') fail(`policy.runtimeLane must be "stage0-free hxhx"`)

  if (!policy.thresholds || typeof policy.thresholds !== 'object') {
    fail('policy.thresholds must be an object')
  } else {
    requirePositiveNumber(policy.thresholds, 'requiredCategoryMedianMaxRatio', 'thresholds')
    requirePositiveNumber(policy.thresholds, 'requiredWorkloadHardCeilingRatio', 'thresholds')
    requirePositiveNumber(policy.thresholds, 'rssHardCeilingRatio', 'thresholds')
    if (policy.thresholds.requiredCategoryMedianMaxRatio > 1.0) {
      fail('thresholds.requiredCategoryMedianMaxRatio must preserve the hxhx <= upstream claim')
    }
  }

  if (!policy.noise || typeof policy.noise !== 'object') {
    fail('policy.noise must be an object')
  } else {
    requirePositiveNumber(policy.noise, 'warmupRuns', 'noise')
    requirePositiveNumber(policy.noise, 'measuredRepetitions', 'noise')
    requirePositiveNumber(policy.noise, 'maxCoefficientOfVariationPct', 'noise')
    requirePositiveNumber(policy.noise, 'retryNoisyWorkloads', 'noise')
    if (policy.noise.aggregation !== 'median') fail('noise.aggregation must be median')
    if (policy.noise.measuredRepetitions < 5) fail('noise.measuredRepetitions must be at least 5')
  }

  const packageScripts = packageJson && packageJson.scripts ? packageJson.scripts : {}
  if (!Array.isArray(policy.workloads) || policy.workloads.length < 3) {
    fail('policy.workloads must define at least three required workloads')
  } else {
    for (const workload of policy.workloads) checkWorkload(workload, packageScripts)
  }

  if (parityMapJson && Array.isArray(parityMapJson.entries)) {
    const markers = new Set(parityMapJson.entries.map(entry => entry.marker))
    if (!markers.has('FULL1_PERF_POLICY:PASS')) {
      fail(`${parityMapJsonPath} must register FULL1_PERF_POLICY:PASS`)
    }
    if (!markers.has('FULL1_PERF_PARITY:PASS')) {
      fail(`${parityMapJsonPath} must register FULL1_PERF_PARITY:PASS`)
    }
  }

  if (process.exitCode) return
  console.log('[ci:guards] OK: Full1 performance parity policy is valid')
  console.log('FULL1_PERF_POLICY:PASS')
}

main()
