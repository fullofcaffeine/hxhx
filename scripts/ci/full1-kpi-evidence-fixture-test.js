#!/usr/bin/env node
/**
 * Synthetic fixture tests for the KPI-to-Full1 evidence adapter.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const childProcess = require('child_process')

const repoRoot = process.cwd()
const adapter = path.join(repoRoot, 'scripts/ci/full1-kpi-evidence.js')

function fail(message) {
  console.error(`[full1-kpi-evidence-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function metric(metricName, lane, values) {
  return {
    metric: metricName,
    lane,
    unit: metricName.endsWith('_kb') ? 'kb' : 'ms',
    summary: {
      count: values.length,
      samples: values
    }
  }
}

function writeJson(filePath, payload) {
  fs.writeFileSync(filePath, JSON.stringify(payload, null, 2) + '\n')
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-kpi-evidence-fixtures-'))
  const reportPath = path.join(tmpDir, 'kpi.report.json')
  const evidencePath = path.join(tmpDir, 'full1-kpi.evidence.json')
  const metrics = []
  for (const metricName of ['compile_wall_ms', 'incremental_rebuild_ms', 'macro_overhead_ms', 'peak_rss_kb']) {
    metrics.push(metric(metricName, 'upstream_haxe', [100, 101, 99, 100, 100]))
    metrics.push(metric(metricName, 'ocaml_metal_builtin', [90, 91, 89, 90, 90]))
  }
  writeJson(reportPath, {
    schema: 'hxhx.kpi.v1',
    metrics
  })

  const result = childProcess.spawnSync(
    process.execPath,
    [adapter, '--kpi-report', reportPath, '--json-out', evidencePath],
    {
      cwd: repoRoot,
      encoding: 'utf8'
    }
  )
  if (result.status !== 0) {
    fail(`adapter failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  const evidence = JSON.parse(fs.readFileSync(evidencePath, 'utf8'))
  if (evidence.schema !== 'full1-perf-evidence.v1') fail(`unexpected evidence schema: ${evidence.schema}`)
  if (evidence.workloads.length !== 1) fail(`expected one workload, got ${evidence.workloads.length}`)
  const workload = evidence.workloads[0]
  if (workload.id !== 'full1-kpi-compile-and-macro') fail(`unexpected workload id: ${workload.id}`)
  if (workload.samples.length !== 8) fail(`expected 8 sample rows, got ${workload.samples.length}`)
  if (!workload.samples.some(sample => sample.metric === 'compile_wall_ms' && sample.lane === 'hxhx')) {
    fail('adapter did not normalize selected hxhx lane')
  }
  fs.rmSync(tmpDir, { recursive: true, force: true })
  console.log('[ci:guards] OK: Full1 KPI evidence adapter synthetic fixture passes')
}

main()
