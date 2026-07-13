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

/**
 * Runs the adapter with synthetic candidate metadata isolated from the GitHub
 * job that happens to be executing this fixture. Individual cases may add
 * candidate metadata back through `env` when that metadata is what they test.
 */
function runAdapter(reportPath, evidencePath, env = {}) {
  const childEnv = { ...process.env }
  for (const name of ['GITHUB_SHA', 'GITHUB_REF', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT']) {
    delete childEnv[name]
  }
  Object.assign(childEnv, env)
  return childProcess.spawnSync(
    process.execPath,
    [adapter, '--kpi-report', reportPath, '--json-out', evidencePath],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: childEnv
    }
  )
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
  const report = {
    schema: 'hxhx.kpi.v2',
    generated_at_utc: '2026-07-13T00:00:00.000Z',
    git: {
      commit: '0123456789abcdef0123456789abcdef01234567',
      tracked_source_clean: true
    },
    config: {
      reps: 5,
      run_macro_lane: true
    },
    environment: {
      platform: 'Linux-fixture',
      os: 'Linux',
      os_release: 'fixture',
      architecture: 'x86_64',
      cpu_model: 'fixture cpu',
      python_version: '3.13.0',
      haxe_bin: 'haxe',
      haxe_version: '4.3.7',
      hxhx_bin: '.hxhx/cache/hxhx-stage3/hxhx',
      hxhx_artifact_kind: 'native-executable',
      node_version: 'v24.0.0',
      ocaml_version: '5.2.1',
      dune_version: '3.17.0'
    },
    measurement: {
      command: 'npm run hxhx:bench:kpi',
      source: 'scripts/hxhx/bench-kpi.sh',
      repetitions: 5,
      raw_samples_embedded: true,
      warmup_runs: {
        compile_wall_ms: 0,
        incremental_rebuild_ms: 1,
        macro_overhead_ms: 0,
        peak_rss_kb: 0
      },
      states: {
        compile_wall_ms: 'compiler invocation with a reused compiler binary',
        incremental_rebuild_ms: 'unchanged input after one unrecorded warmup invocation',
        macro_overhead_ms: 'macro-enabled time minus its paired baseline compile',
        peak_rss_kb: 'maximum resident set size for the measured compiler process tree'
      }
    },
    metrics
  }
  writeJson(reportPath, report)

  const result = runAdapter(reportPath, evidencePath)
  if (result.status !== 0) {
    fail(`adapter failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  const evidence = JSON.parse(fs.readFileSync(evidencePath, 'utf8'))
  if (evidence.schema !== 'full1-perf-evidence.v1') fail(`unexpected evidence schema: ${evidence.schema}`)
  if (evidence.git.sha !== '0123456789abcdef0123456789abcdef01234567') {
    fail(`unexpected evidence commit: ${evidence.git.sha}`)
  }
  if (evidence.runner.inputSchema !== 'hxhx.kpi.v2') {
    fail(`unexpected input schema: ${evidence.runner.inputSchema}`)
  }
  if (evidence.workloads.length !== 1) fail(`expected one workload, got ${evidence.workloads.length}`)
  const workload = evidence.workloads[0]
  if (workload.id !== 'full1-kpi-compile-and-macro') fail(`unexpected workload id: ${workload.id}`)
  if (workload.samples.length !== 8) fail(`expected 8 sample rows, got ${workload.samples.length}`)
  if (!workload.samples.some(sample => sample.metric === 'compile_wall_ms' && sample.lane === 'hxhx')) {
    fail('adapter did not normalize selected hxhx lane')
  }

  report.git.tracked_source_clean = false
  writeJson(reportPath, report)
  const dirtyResult = runAdapter(reportPath, evidencePath)
  if (dirtyResult.status === 0 || !dirtyResult.stderr.includes('tracked source changes')) {
    fail('adapter must reject a KPI report measured from dirty tracked source')
  }

  report.git.tracked_source_clean = true
  writeJson(reportPath, report)
  const crossShaResult = runAdapter(reportPath, evidencePath, {
    GITHUB_SHA: 'fedcba9876543210fedcba9876543210fedcba98'
  })
  if (crossShaResult.status === 0 || !crossShaResult.stderr.includes('does not match GITHUB_SHA')) {
    fail('adapter must reject KPI evidence from a different candidate SHA')
  }
  fs.rmSync(tmpDir, { recursive: true, force: true })
  console.log('[ci:guards] OK: Full1 KPI evidence adapter synthetic fixture passes')
}

main()
