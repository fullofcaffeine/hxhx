#!/usr/bin/env node
/**
 * Synthetic fixture tests for full1-perf-evaluator.js.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const childProcess = require('child_process')

const repoRoot = process.cwd()
const evaluator = path.join(repoRoot, 'scripts/ci/full1-perf-evaluator.js')

function fail(message) {
  console.error(`[full1-perf-evaluator-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function writeJson(filePath, payload) {
  fs.writeFileSync(filePath, JSON.stringify(payload, null, 2) + '\n')
}

function workload(workloadId, metricPairs) {
  const samples = []
  for (const [metric, upstreamValues, hxhxValues] of metricPairs) {
    samples.push({
      metric,
      lane: 'upstream_haxe',
      values: upstreamValues
    })
    samples.push({
      metric,
      lane: 'hxhx',
      values: hxhxValues
    })
  }
  return {
    id: workloadId,
    samples
  }
}

function evidence(firstWorkloadMetrics) {
  const compilePass = [
    ['compile_wall_ms', [100, 101, 99, 100, 100], [90, 91, 89, 90, 90]],
    ['peak_rss_kb', [1000, 1001, 999, 1000, 1000], [900, 901, 899, 900, 900]],
    ['incremental_rebuild_ms', [50, 51, 49, 50, 50], [45, 46, 44, 45, 45]],
    ['macro_overhead_ms', [10, 10, 10, 10, 10], [9, 9, 9, 9, 9]]
  ]
  const evalPass = [['compile_wall_ms', [100, 101, 99, 100, 100], [90, 91, 89, 90, 90]]]
  const suitePass = [
    ['compile_wall_ms', [100, 101, 99, 100, 100], [90, 91, 89, 90, 90]],
    ['peak_rss_kb', [1000, 1001, 999, 1000, 1000], [900, 901, 899, 900, 900]]
  ]
  return {
    schema: 'full1-perf-evidence.v1',
    haxeCompatibilityBaseline: '4.3.7',
    workloads: [
      workload('full1-kpi-compile-and-macro', firstWorkloadMetrics || compilePass),
      workload('full1-native-eval-latency', evalPass),
      workload('full1-upstream-suite-compiler-workloads', suitePass)
    ]
  }
}

function partialEvidence() {
  return {
    schema: 'full1-perf-evidence.v1',
    haxeCompatibilityBaseline: '4.3.7',
    workloads: [
      workload('full1-kpi-compile-and-macro', [
        ['compile_wall_ms', [100, 101, 99, 100, 100], [90, 91, 89, 90, 90]],
        ['peak_rss_kb', [1000, 1001, 999, 1000, 1000], [900, 901, 899, 900, 900]],
        ['incremental_rebuild_ms', [50, 51, 49, 50, 50], [45, 46, 44, 45, 45]],
        ['macro_overhead_ms', [10, 10, 10, 10, 10], [9, 9, 9, 9, 9]]
      ])
    ]
  }
}

function runCase(tmpDir, name, payload, expectedExit, expectedDecision) {
  const evidencePath = path.join(tmpDir, `${name}.evidence.json`)
  const outPath = path.join(tmpDir, `${name}.evaluation.json`)
  writeJson(evidencePath, payload)
  const result = childProcess.spawnSync(process.execPath, [evaluator, '--evidence', evidencePath, '--json-out', outPath], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== expectedExit) {
    fail(`${name}: expected exit ${expectedExit}, got ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  if (!fs.existsSync(outPath)) fail(`${name}: evaluator did not write summary`)
  const summary = JSON.parse(fs.readFileSync(outPath, 'utf8'))
  if (summary.decision !== expectedDecision) {
    fail(`${name}: expected decision ${expectedDecision}, got ${summary.decision}`)
  }
  if (expectedDecision === 'pass' && !String(result.stdout).includes('FULL1_PERF_PARITY:PASS')) {
    fail(`${name}: pass case did not emit FULL1_PERF_PARITY:PASS`)
  }
  if (expectedDecision !== 'pass' && String(result.stdout).includes('FULL1_PERF_PARITY:PASS')) {
    fail(`${name}: failing case emitted FULL1_PERF_PARITY:PASS`)
  }
  return summary
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-perf-evaluator-fixtures-'))
  const passSummary = runCase(
    tmpDir,
    'pass',
    evidence(),
    0,
    'pass'
  )
  if (passSummary.marker !== 'FULL1_PERF_PARITY:PASS') fail('pass summary marker mismatch')

  runCase(
    tmpDir,
    'near-zero-delta-pass',
    evidence([
      ['compile_wall_ms', [100, 101, 99, 100, 100], [90, 91, 89, 90, 90]],
      ['peak_rss_kb', [1000, 1001, 999, 1000, 1000], [900, 901, 899, 900, 900]],
      ['incremental_rebuild_ms', [50, 51, 49, 50, 50], [45, 46, 44, 45, 45]],
      ['macro_overhead_ms', [53, 55, 52, 54, 53], [0, 2, 1, 0, 3]]
    ]),
    0,
    'pass'
  )

  const thresholdSummary = runCase(
    tmpDir,
    'threshold-fail',
    evidence([
      ['compile_wall_ms', [100, 101, 99, 100, 100], [120, 121, 119, 120, 120]],
      ['peak_rss_kb', [1000, 1001, 999, 1000, 1000], [900, 901, 899, 900, 900]],
      ['incremental_rebuild_ms', [50, 51, 49, 50, 50], [45, 46, 44, 45, 45]],
      ['macro_overhead_ms', [10, 10, 10, 10, 10], [9, 9, 9, 9, 9]]
    ]),
    1,
    'fail'
  )
  if (!JSON.stringify(thresholdSummary.failures).includes('hard ceiling')) {
    fail('threshold fail summary did not record hard ceiling failure')
  }

  const noisySummary = runCase(
    tmpDir,
    'noise-fail',
    evidence([
      ['compile_wall_ms', [100, 100, 100, 100, 100], [20, 180, 100, 100, 100]],
      ['peak_rss_kb', [1000, 1001, 999, 1000, 1000], [900, 901, 899, 900, 900]],
      ['incremental_rebuild_ms', [50, 51, 49, 50, 50], [45, 46, 44, 45, 45]],
      ['macro_overhead_ms', [10, 10, 10, 10, 10], [9, 9, 9, 9, 9]]
    ]),
    1,
    'fail'
  )
  if (!JSON.stringify(noisySummary.failures).includes('noisy')) {
    fail('noise fail summary did not record noisy sample failure')
  }

  const partialSummary = runCase(tmpDir, 'partial-fail', partialEvidence(), 1, 'fail')
  if (!JSON.stringify(partialSummary.failures).includes('missing required workload')) {
    fail('partial fail summary did not record missing required workload failure')
  }

  fs.rmSync(tmpDir, { recursive: true, force: true })
  console.log('[ci:guards] OK: Full1 perf evaluator synthetic fixtures pass')
}

main()
