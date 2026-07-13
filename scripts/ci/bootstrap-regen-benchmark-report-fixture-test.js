#!/usr/bin/env node
/**
 * Exercise bootstrap-regeneration report validation with synthetic evidence.
 */

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = process.cwd()
const validator = path.join(repoRoot, 'scripts/ci/bootstrap-regen-benchmark-report.js')
const digest = 'a'.repeat(64)

function fail(message) {
  console.error(`[bootstrap-regen-benchmark-report-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function metricSummary(samples) {
  return {
    count: samples.length,
    min: Math.min(...samples),
    max: Math.max(...samples),
    median: (samples[0] + samples[1]) / 2,
    samples
  }
}

function validReport() {
  const runs = [
    {
      scenario: 'warm',
      policy: 'warn',
      dune_jobs: 'auto',
      rep: 1,
      elapsed_sec: 10,
      emit_sec: 8,
      total_sec: 9,
      skipped_emit: false,
      haxe_bin_mode: 'wrapper',
      haxe_bin_policy: 'warn',
      haxe_bin_switched: false,
      haxe_version: '4.3.7',
      haxe_native_candidate: 'haxe',
      peak_rss_mb: 100,
      source_report: { path: 'warm.warn.jobsauto.run1.json', sha256: digest }
    },
    {
      scenario: 'warm',
      policy: 'warn',
      dune_jobs: 'auto',
      rep: 2,
      elapsed_sec: 12,
      emit_sec: 10,
      total_sec: 11,
      skipped_emit: false,
      haxe_bin_mode: 'wrapper',
      haxe_bin_policy: 'warn',
      haxe_bin_switched: false,
      haxe_version: '4.3.7',
      haxe_native_candidate: 'haxe',
      peak_rss_mb: 120,
      source_report: { path: 'warm.warn.jobsauto.run2.json', sha256: digest }
    }
  ]
  return {
    schema: 'hxhx.bootstrap-regen-benchmark.v1',
    artifact_kind: 'bootstrap-snapshot-regeneration',
    generated_at_utc: '2026-07-13T00:00:00.000Z',
    diagnostic_only: true,
    git: {
      commit: '0123456789abcdef0123456789abcdef01234567',
      tracked_source_clean_at_start: true,
      tracked_source_clean_at_end: true
    },
    environment: {
      os: 'Linux',
      os_release: 'fixture',
      architecture: 'x64',
      cpu_model: 'fixture cpu',
      haxe_bin: 'haxe',
      haxe_version: '4.3.7',
      node_version: 'v20.0.0',
      ocaml_version: '5.2.1',
      dune_version: '3.17.0'
    },
    config: {
      scenarios: ['warm'],
      reps: 2,
      verify_snapshots: false,
      dune_jobs: ['auto'],
      compare_stage0_policies: false,
      stage0_policy_override: 'warn',
      stage0_native_candidate: 'auto',
      stage0_no_opt: false,
      stage0_no_inline: false,
      stage0_disable_prepasses: false,
      stage0_ocamlrunparam: ''
    },
    measurement: {
      command: 'npm run hxhx:bench:bootstrap-regen',
      source: 'scripts/hxhx/bench-bootstrap-regen.sh',
      elapsed_clock: 'wall-clock seconds',
      threshold_policy: 'report-only',
      raw_runs_embedded: true,
      per_run_reports_retained: true,
      scenario_definitions: {
        cold: 'full regeneration after removing prior generated output',
        warm: 'forced incremental regeneration while reusing the repository Haxe server',
        skip: 'unchanged-input check after one unmeasured fingerprint-priming regeneration',
        select: 'stage0 compiler selection only; no snapshot regeneration'
      },
      warmup_rules: {
        cold: 'none',
        warm: 'no explicit warmup; repetitions reuse the repository Haxe server',
        skip: 'one unmeasured forced incremental regeneration before each measured unchanged-input check',
        select: 'none'
      }
    },
    run_count: 2,
    runs,
    summaries: [
      {
        scenario: 'warm',
        policy: 'warn',
        dune_jobs: 'auto',
        elapsed_sec: metricSummary([10, 12]),
        emit_sec: metricSummary([8, 10]),
        total_sec: metricSummary([9, 11]),
        peak_rss_mb: metricSummary([100, 120])
      }
    ]
  }
}

function runValidator(report, expectedStatus, label, tmpDir) {
  const reportPath = path.join(tmpDir, `${label}.json`)
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
  const result = childProcess.spawnSync(process.execPath, [validator, 'validate', '--report', reportPath], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== expectedStatus) {
    fail(`${label}: expected exit ${expectedStatus}, received ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-bootstrap-regen-report-fixtures-'))
  try {
    runValidator(validReport(), 0, 'valid', tmpDir)
    const cases = [
      ['missing-provenance', report => { delete report.environment.cpu_model }],
      ['row-count-mismatch', report => { report.config.reps = 3 }],
      ['invalid-scenario', report => { report.runs[0].scenario = 'mystery' }],
      ['summary-mismatch', report => { report.summaries[0].elapsed_sec.median = 1 }],
      ['absolute-source-report', report => { report.runs[0].source_report.path = '/tmp/run.json' }]
    ]
    for (const [label, mutate] of cases) {
      const report = validReport()
      mutate(report)
      runValidator(report, 1, label, tmpDir)
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
  console.log('[ci:guards] OK: bootstrap regeneration report fixtures pass')
}

main()
