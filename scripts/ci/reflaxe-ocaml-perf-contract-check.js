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

  const iteration = baseline.iterationScenario
  if (!iteration || iteration.id !== 'ro-iteration-01'
    || iteration.kind !== 'authoring_iteration'
    || iteration.exampleDir !== 'packages/reflaxe.ocaml/examples/build-macro'
    || iteration.outDir !== 'out'
    || iteration.executableRelativePath !== 'out/_build/default/out.exe'
    || iteration.warmupCycles !== 1
    || iteration.measuredCycles !== 3
    || JSON.stringify(iteration.stateOrder) !== JSON.stringify(['cold-output', 'warm-unchanged', 'one-file-change'])
    || JSON.stringify(iteration.compileArgs) !== JSON.stringify(['build.hxml', '-D', 'ocaml_build=native', '-D', 'ocaml_build_timing_report'])
    || iteration.sourceChange?.relativePath !== 'src/BuildMacro.hx'
    || iteration.sourceChange?.before !== '"from_build_macro"'
    || iteration.sourceChange?.after !== '"from_build_macro_changed"'
    || iteration.expectedOutputChange?.before !== 'from_build_macro'
    || iteration.expectedOutputChange?.after !== 'from_build_macro_changed') {
    fail('baseline standalone iteration scenario changed its controlled measurement contract')
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

  for (const marker of ['RO_TARGET_PERF_CREDIBLE:PASS', 'RO_TARGET_ITERATION_REPORT:PASS']) {
    if (!contract.includes(marker)) {
      fail(`${contractPath} must reference ${marker}`)
    }
  }
  if (!contract.includes('REFLAXE_OCAML_PERF_CREDIBILITY.md')) {
    fail(`${contractPath} must reference the perf credibility doc`)
  }
  if (!perfDoc.includes('RO_TARGET_PERF_CREDIBLE:PASS')) {
    fail(`${perfDocPath} must include RO_TARGET_PERF_CREDIBLE:PASS`)
  }
  for (const needle of [
    'scripts/ci/run-reflaxe-ocaml-perf.js',
    'scripts/ci/run-reflaxe-ocaml-iteration-perf.js',
    'RO_TARGET_ITERATION_REPORT:PASS',
    'installed-package-platform-v2',
    'cold-output',
    'warm-unchanged',
    'one-file-change',
    'report-only-until-stable-hosted-trend'
  ]) {
    if (!perfDoc.includes(needle)) {
      fail(`${perfDocPath} must include ${needle}`)
    }
  }
  for (const marker of ['RO_TARGET_PERF_PLATFORM:PASS', 'RO_TARGET_PERF_PLATFORM_MATRIX:PASS']) {
    if (!contract.includes(marker) || !perfDoc.includes(marker)) {
      fail(`contract and performance docs must explain ${marker}`)
    }
  }
  for (const needle of [
    'RO_PERF_MODE=platform-report',
    's.schemaVersion !== 2',
    's.method?.id !== "installed-package-platform-v2"',
    's.iteration?.passed !== true',
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
  if (packageJson.scripts['test:reflaxe-ocaml:iteration-perf']
    !== 'node scripts/ci/run-reflaxe-ocaml-iteration-perf.js') {
    fail(`${packagePath} must expose the focused standalone iteration command`)
  }

  console.log('[ci:guards] OK: reflaxe.ocaml perf credibility contract is valid')
  console.log('RO_TARGET_PERF_CREDIBLE:PASS')
}

main()
