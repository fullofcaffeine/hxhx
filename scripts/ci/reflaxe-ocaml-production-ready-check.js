#!/usr/bin/env node
const fs = require('fs')
const path = require('path')

const root = process.cwd()
const paths = {
  contract: 'docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md',
  guide: 'docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md',
  matrixSummary: '.artifacts/reflaxe-ocaml/haxe-matrix/summary.json',
  closureAudit: 'docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.json',
  perfSummary: '.artifacts/reflaxe-ocaml/perf/summary.json',
}

function fail(message) {
  console.error(`[reflaxe-ocaml-production-ready] ERROR: ${message}`)
  process.exit(1)
}

function readText(relPath) {
  const abs = path.join(root, relPath)
  if (!fs.existsSync(abs)) fail(`missing file: ${relPath}`)
  return fs.readFileSync(abs, 'utf8')
}

function readJson(relPath) {
  return JSON.parse(readText(relPath))
}

function requireIncludes(text, needle, label) {
  if (!text.includes(needle)) fail(`${label} must include ${needle}`)
}

function requireAllPassed(entries, label) {
  if (!Array.isArray(entries) || entries.length === 0) fail(`${label} must be a non-empty array`)
  for (const entry of entries) {
    if (entry.passed !== true) fail(`${label} entry ${entry.id || entry.name || '<unknown>'} did not pass`)
  }
}

function main() {
  const contract = readText(paths.contract)
  const guide = readText(paths.guide)
  const matrix = readJson(paths.matrixSummary)
  const closure = readJson(paths.closureAudit)
  const perf = readJson(paths.perfSummary)

  for (const marker of [
    'RO_HAXE_4_3_7_MATRIX:PASS',
    'RO_RUNTIME_STDLIB_CLOSURE:PASS',
    'RO_TARGET_PERF_CREDIBLE:PASS',
    'RO_PRODUCTION_DOCS:PASS',
    'RO_PRODUCTION_READY:PASS',
  ]) {
    requireIncludes(contract, marker, paths.contract)
  }
  requireIncludes(guide, 'RO_PRODUCTION_READY:PASS', paths.guide)

  if (matrix.marker !== 'RO_HAXE_4_3_7_MATRIX:PASS') fail(`unexpected matrix marker ${matrix.marker}`)
  if (matrix.baseline !== '4.3.7') fail(`matrix baseline must be 4.3.7, got ${matrix.baseline}`)
  requireAllPassed(matrix.workloads, 'matrix.workloads')

  if (closure.marker !== 'RO_RUNTIME_STDLIB_CLOSURE:PASS') fail(`unexpected closure marker ${closure.marker}`)
  if (closure.haxeCompatibilityBaseline !== '4.3.7') {
    fail(`closure baseline must be 4.3.7, got ${closure.haxeCompatibilityBaseline}`)
  }
  if (!Array.isArray(closure.entries) || closure.entries.length === 0) fail('closure audit entries must be non-empty')

  if (perf.marker !== 'RO_TARGET_PERF_CREDIBLE:PASS') fail(`unexpected perf marker ${perf.marker}`)
  if (!perf.environment || perf.environment.haxe !== '4.3.7') {
    fail(`perf summary must record haxe 4.3.7, got ${perf.environment && perf.environment.haxe}`)
  }
  requireAllPassed(perf.scenarios, 'perf.scenarios')

  const summaryOut = process.env.RO_PRODUCTION_READY_SUMMARY_OUT
  if (summaryOut) {
    const payload = {
      marker: 'RO_PRODUCTION_READY:PASS',
      scope: 'reflaxe.ocaml standalone target product for upstream Haxe 4.3.7',
      evidence: {
        matrixSummary: paths.matrixSummary,
        closureAudit: paths.closureAudit,
        perfSummary: paths.perfSummary,
        productionGuide: paths.guide,
      },
      environment: perf.environment,
    }
    fs.mkdirSync(path.dirname(summaryOut), { recursive: true })
    fs.writeFileSync(summaryOut, JSON.stringify(payload, null, 2) + '\n')
    console.log(`ro_production_ready_summary=${summaryOut}`)
  }

  console.log(`ro_haxe_matrix_summary=${paths.matrixSummary}`)
  console.log(`ro_perf_summary=${paths.perfSummary}`)
  console.log('RO_PRODUCTION_READY:PASS')
}

main()
