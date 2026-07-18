#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const repoRoot = process.cwd()
const contractPath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md')
const perfDocPath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md')
const baselinePath = path.join(repoRoot, 'docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json')
const workflowPath = path.join(repoRoot, '.github/workflows/reflaxe-ocaml-package-matrix.yml')
const packagePath = path.join(repoRoot, 'package.json')

function fail(message) {
  console.error(`[reflaxe-ocaml-perf-contract-check] ERROR: ${message}`)
  process.exit(1)
}

function readText(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function readJson(filePath) {
  return JSON.parse(readText(filePath))
}

function requireMetric(thresholds, name) {
  const entry = thresholds[name]
  if (!entry || typeof entry.value !== 'number' || typeof entry.maxRegressionPct !== 'number') {
    fail(`baseline threshold ${name} is missing numeric value/maxRegressionPct`)
  }
}

function main() {
  const contract = readText(contractPath)
  const perfDoc = readText(perfDocPath)
  const baseline = readJson(baselinePath)
  const workflow = readText(workflowPath)
  const packageJson = readJson(packagePath)

  if (baseline.marker !== 'RO_TARGET_PERF_CREDIBLE:PASS') {
    fail(`unexpected baseline marker ${baseline.marker}`)
  }
  if (!Array.isArray(baseline.scenarios) || baseline.scenarios.length !== 6) {
    fail('baseline must define exactly 6 scenarios')
  }

  for (const scenario of baseline.scenarios) {
    if (!scenario.id || !scenario.kind || !scenario.title) {
      fail('each perf scenario must include id, kind, and title')
    }
    if (!scenario.thresholds || typeof scenario.thresholds !== 'object') {
      fail(`scenario ${scenario.id} is missing thresholds`)
    }
    requireMetric(scenario.thresholds, 'buildMedianMs')
    requireMetric(scenario.thresholds, 'generatedMlBytes')
    requireMetric(scenario.thresholds, 'executableBytes')
    if (scenario.kind === 'runtime_bench') {
      requireMetric(scenario.thresholds, 'runMedianMs')
    }
  }

  if (!baseline.profileComparisonThresholds || typeof baseline.profileComparisonThresholds !== 'object') {
    fail('baseline is missing profileComparisonThresholds')
  }
  requireMetric(baseline.profileComparisonThresholds, 'runMedianPctOfPortable')
  requireMetric(baseline.profileComparisonThresholds, 'buildMedianPctOfPortable')

  if (!contract.includes('RO_TARGET_PERF_CREDIBLE:PASS')) {
    fail(`${contractPath} must reference RO_TARGET_PERF_CREDIBLE:PASS`)
  }
  if (!contract.includes('REFLAXE_OCAML_PERF_CREDIBILITY.md')) {
    fail(`${contractPath} must reference the perf credibility doc`)
  }
  if (!perfDoc.includes('RO_TARGET_PERF_CREDIBLE:PASS')) {
    fail(`${perfDocPath} must include RO_TARGET_PERF_CREDIBLE:PASS`)
  }
  if (!perfDoc.includes('scripts/ci/run-reflaxe-ocaml-perf.js')) {
    fail(`${perfDocPath} must reference the deterministic perf runner`)
  }
  for (const marker of ['RO_TARGET_PERF_PLATFORM:PASS', 'RO_TARGET_PERF_PLATFORM_MATRIX:PASS']) {
    if (!contract.includes(marker) || !perfDoc.includes(marker)) {
      fail(`contract and performance docs must explain ${marker}`)
    }
  }
  for (const needle of [
    'RO_PERF_MODE=platform-report',
    'reflaxe-ocaml-perf-matrix-summary.js',
    'reflaxe-ocaml-perf-matrix-${{ github.sha }}'
  ]) {
    if (!workflow.includes(needle)) {
      fail(`${workflowPath} must include ${needle}`)
    }
  }
  if (packageJson.scripts['test:reflaxe-ocaml:perf-platform']
    !== 'RO_PERF_MODE=platform-report node scripts/ci/run-reflaxe-ocaml-perf.js') {
    fail(`${packagePath} must expose the installed-package performance command`)
  }

  console.log('[ci:guards] OK: reflaxe.ocaml perf credibility contract is valid')
  console.log('RO_TARGET_PERF_CREDIBLE:PASS')
}

main()
