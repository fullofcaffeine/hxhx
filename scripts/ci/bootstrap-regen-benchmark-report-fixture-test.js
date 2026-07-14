#!/usr/bin/env node
/**
 * Exercise bootstrap-regeneration report validation with synthetic evidence.
 */

const childProcess = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = process.cwd()
const validator = path.join(repoRoot, 'scripts/ci/bootstrap-regen-benchmark-report.js')
const runner = path.join(repoRoot, 'scripts/hxhx/bench-bootstrap-regen.sh')
const digest = 'a'.repeat(64)
const { collectWorktreeChanges } = require(validator)

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
      tracked_source_clean_at_end: true,
      bootstrap_snapshot_scope: 'packages/hxhx/bootstrap_out',
      bootstrap_snapshot_clean_at_end: true,
      bootstrap_snapshot_changes: []
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
      stage0_policy_meaning: 'wrapper uses the upstream-Haxe launcher; native uses the direct upstream-Haxe executable. Neither label means native hxhx.',
      peak_rss_scope: 'focused stage0 client process only; the repository Haxe server and total job memory are not included',
      scenario_definitions: {
        cold: 'full regeneration after removing prior generated output',
        warm: 'forced incremental regeneration with primed generated output and a fresh policy-matched repository Haxe server for each sample',
        skip: 'unchanged-input check after one unmeasured fingerprint-priming regeneration',
        select: 'stage0 compiler selection only; no snapshot regeneration'
      },
      warmup_rules: {
        cold: 'none',
        warm: 'one unmeasured forced incremental regeneration primes generated output; every measured sample starts and stops a fresh policy-matched repository Haxe server',
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

function runGit(cwd, args) {
  const result = childProcess.spawnSync('git', args, { cwd, encoding: 'utf8' })
  if (result.status !== 0) fail(`git ${args.join(' ')} failed: ${result.stderr || result.stdout}`)
  return result.stdout.trim()
}

function contentDigest(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function assertWorktreeChangeCollection(tmpDir) {
  const fixtureRepo = path.join(tmpDir, 'worktree-change-repo')
  const scope = 'packages/hxhx/bootstrap_out'
  const snapshotDir = path.join(fixtureRepo, scope)
  fs.mkdirSync(snapshotDir, { recursive: true })
  runGit(fixtureRepo, ['init', '-q'])
  runGit(fixtureRepo, ['config', 'user.name', 'Fixture'])
  runGit(fixtureRepo, ['config', 'user.email', 'fixture@example.invalid'])
  fs.writeFileSync(path.join(snapshotDir, 'changed.ml'), 'before\n')
  fs.writeFileSync(path.join(snapshotDir, 'deleted.ml'), 'delete me\n')
  runGit(fixtureRepo, ['add', '.'])
  runGit(fixtureRepo, ['commit', '-qm', 'fixture baseline'])
  const commit = runGit(fixtureRepo, ['rev-parse', 'HEAD'])

  fs.writeFileSync(path.join(snapshotDir, 'changed.ml'), 'after\n')
  fs.rmSync(path.join(snapshotDir, 'deleted.ml'))
  fs.writeFileSync(path.join(snapshotDir, 'added.ml'), 'new\n')

  const changes = collectWorktreeChanges(fixtureRepo, commit, scope)
  if (changes.length !== 3) fail(`expected three captured worktree changes, received ${changes.length}`)
  const byPath = new Map(changes.map(change => [path.basename(change.path), change]))
  const changed = byPath.get('changed.ml')
  const deleted = byPath.get('deleted.ml')
  const added = byPath.get('added.ml')
  if (changed?.kind !== 'modified'
      || changed.before_sha256 !== contentDigest('before\n')
      || changed.after_sha256 !== contentDigest('after\n')) {
    fail('modified snapshot path did not preserve before/after digests')
  }
  if (deleted?.kind !== 'deleted'
      || deleted.before_sha256 !== contentDigest('delete me\n')
      || deleted.after_sha256 !== null) {
    fail('deleted snapshot path did not preserve its before digest')
  }
  if (added?.kind !== 'added'
      || added.before_sha256 !== null
      || added.after_sha256 !== contentDigest('new\n')) {
    fail('untracked snapshot path did not preserve its after digest')
  }
}

function main() {
  const runnerSource = fs.readFileSync(runner, 'utf8')
  const warmRunner = runnerSource.match(/run_scenario_warm\(\) \{([\s\S]*?)\n\}/)
  if (!warmRunner) fail('could not locate run_scenario_warm in the benchmark runner')
  if (!warmRunner[1].includes('--incremental --use-repo-server --force')) {
    fail('warm samples must use incremental output with a policy-matched repo server')
  }
  if (warmRunner[1].includes('--keep-repo-server')) {
    fail('warm samples must not share one Haxe server across measurements')
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-bootstrap-regen-report-fixtures-'))
  try {
    assertWorktreeChangeCollection(tmpDir)
    runValidator(validReport(), 0, 'valid', tmpDir)
    const legacyReport = validReport()
    legacyReport.measurement.scenario_definitions.warm = 'forced incremental regeneration while reusing the repository Haxe server'
    legacyReport.measurement.warmup_rules.warm = 'no explicit warmup; repetitions reuse the repository Haxe server'
    delete legacyReport.measurement.stage0_policy_meaning
    delete legacyReport.measurement.peak_rss_scope
    delete legacyReport.git.bootstrap_snapshot_scope
    delete legacyReport.git.bootstrap_snapshot_clean_at_end
    delete legacyReport.git.bootstrap_snapshot_changes
    runValidator(legacyReport, 0, 'legacy-v1', tmpDir)
    const cases = [
      ['missing-provenance', report => { delete report.environment.cpu_model }],
      ['missing-stage0-policy-meaning', report => { delete report.measurement.stage0_policy_meaning }],
      ['row-count-mismatch', report => { report.config.reps = 3 }],
      ['invalid-scenario', report => { report.runs[0].scenario = 'mystery' }],
      ['summary-mismatch', report => { report.summaries[0].elapsed_sec.median = 1 }],
      ['absolute-source-report', report => { report.runs[0].source_report.path = '/tmp/run.json' }],
      ['snapshot-clean-mismatch', report => { report.git.bootstrap_snapshot_clean_at_end = false }],
      ['absolute-snapshot-path', report => {
        report.git.bootstrap_snapshot_clean_at_end = false
        report.git.bootstrap_snapshot_changes.push({
          kind: 'added',
          path: '/tmp/generated.ml',
          before_sha256: null,
          after_sha256: digest
        })
      }],
      ['invalid-snapshot-digest', report => {
        report.git.bootstrap_snapshot_clean_at_end = false
        report.git.bootstrap_snapshot_changes.push({
          kind: 'modified',
          path: 'packages/hxhx/bootstrap_out/changed.ml',
          before_sha256: 'not-a-digest',
          after_sha256: digest
        })
      }]
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
