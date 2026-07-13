#!/usr/bin/env node
/**
 * Exercise the self-describing hxhx KPI report contract with synthetic data.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const childProcess = require('child_process')

const repoRoot = process.cwd()
const validator = path.join(repoRoot, 'scripts/ci/hxhx-kpi-report-validator.js')

function fail(message) {
  console.error(`[hxhx-kpi-report-validator-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function validReport() {
  const states = {
    compile_wall_ms: 'compiler invocation with a reused compiler binary',
    incremental_rebuild_ms: 'unchanged input after one unrecorded warmup invocation',
    macro_overhead_ms: 'macro-enabled time minus its paired baseline compile',
    peak_rss_kb: 'maximum resident set size for the measured compiler process tree'
  }
  return {
    schema: 'hxhx.kpi.v2',
    generated_at_utc: '2026-07-13T00:00:00.000Z',
    git: {
      commit: '0123456789abcdef0123456789abcdef01234567',
      tracked_source_clean: true
    },
    config: {
      reps: 2,
      run_macro_lane: true
    },
    environment: {
      platform: 'Linux-test',
      os: 'Linux',
      os_release: 'test',
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
      repetitions: 2,
      raw_samples_embedded: true,
      warmup_runs: {
        compile_wall_ms: 0,
        incremental_rebuild_ms: 1,
        macro_overhead_ms: 0,
        peak_rss_kb: 0
      },
      states
    },
    metrics: [
      {
        metric: 'compile_wall_ms',
        lane: 'upstream_haxe',
        unit: 'ms',
        summary: {
          count: 2,
          min: 99,
          max: 100,
          mean: 99.5,
          median: 99,
          p95: 100,
          samples: [99, 100]
        }
      }
    ],
    lane_ratios: []
  }
}

function runValidator(report, expectedStatus, label, tmpDir) {
  const reportPath = path.join(tmpDir, `${label}.json`)
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
  const result = childProcess.spawnSync(process.execPath, [validator, '--report', reportPath], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== expectedStatus) {
    fail(`${label}: expected exit ${expectedStatus}, received ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-kpi-report-fixtures-'))
  try {
    runValidator(validReport(), 0, 'valid', tmpDir)

    const cases = [
      ['old-schema', report => { report.schema = 'hxhx.kpi.v1' }],
      ['missing-timestamp', report => { delete report.generated_at_utc }],
      ['missing-commit', report => { delete report.git.commit }],
      ['malformed-commit', report => { report.git.commit = 'abc123' }],
      ['absolute-hxhx-path', report => { report.environment.hxhx_bin = '/tmp/hxhx' }],
      ['missing-toolchain', report => { delete report.environment.ocaml_version }],
      ['wrong-repetitions', report => { report.measurement.repetitions = 3 }],
      ['sample-count-mismatch', report => { report.metrics[0].summary.count = 1 }]
    ]
    for (const [label, mutate] of cases) {
      const report = validReport()
      mutate(report)
      runValidator(report, 1, label, tmpDir)
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
  console.log('[ci:guards] OK: hxhx KPI report provenance fixtures pass')
}

main()
