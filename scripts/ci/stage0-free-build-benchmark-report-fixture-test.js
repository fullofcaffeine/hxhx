#!/usr/bin/env node

/**
 * Synthetic contract tests for stage0-free native-build reports. These prove
 * report/resource validation only; they are not build or performance evidence.
 */

const childProcess = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = process.cwd()
const validator = path.join(repoRoot, 'scripts/ci/stage0-free-build-benchmark-report.js')
const resourceHelper = path.join(repoRoot, 'scripts/ci/measure-command-resources.py')
const runner = path.join(repoRoot, 'scripts/hxhx/bench-stage0-free-build.sh')
const {
  artifactKind,
  buildCommand,
  buildComparison,
  evidenceLevel,
  laneDefinitions,
  laneOrder,
  measurementContract,
  passMarker,
  requiredSmokeTargets,
  resourceSchema,
  resourceScope,
  schema,
  summarizeRuns
} = require(validator)

const commit = '0123456789abcdef0123456789abcdef01234567'

function fail(message) {
  console.error(`[stage0-free-build-benchmark-report-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function evidencePlaceholder(filePath) {
  return {
    path: filePath,
    sha256: 'a'.repeat(64),
    size_bytes: 1
  }
}

function runRow(lane, rep, order, elapsedMs, rssKb) {
  const prefix = `runs/sample.${rep}.${lane}`
  return {
    lane,
    rep,
    order,
    elapsed_ms: elapsedMs,
    peak_child_rss_kb: rssKb,
    stage0_forbidden: true,
    artifact_commit: commit,
    resource: evidencePlaceholder(`${prefix}/resource.json`),
    stdout: evidencePlaceholder(`${prefix}/build.stdout.log`),
    stderr: evidencePlaceholder(`${prefix}/build.stderr.log`),
    artifact: {
      ...evidencePlaceholder('artifacts/hxhx-fixture.exe'),
      kind: 'native-executable'
    },
    smoke: {
      ...evidencePlaceholder(`${prefix}/targets.stdout.log`),
      required_targets: requiredSmokeTargets
    }
  }
}

function validReport() {
  const runs = [
    runRow('cache-disabled', 1, 1, 1000, 100000),
    runRow('cache-primed', 1, 2, 400, 80000),
    runRow('cache-primed', 2, 1, 420, 81000),
    runRow('cache-disabled', 2, 2, 1100, 101000)
  ]
  const summaries = summarizeRuns(runs)
  return {
    schema,
    artifact_kind: artifactKind,
    evidence_level: evidenceLevel,
    marker: passMarker,
    recorded_at: '2026-07-14T00:00:00.000Z',
    git: {
      commit,
      tracked_source_clean_at_start: true,
      tracked_source_clean_at_end: true
    },
    environment: {
      os: 'Linux',
      architecture: 'x64',
      cpu_model: 'Fixture CPU',
      node_version: 'v20.0.0',
      haxe_path: 'haxe',
      haxe_version: '4.3.7',
      python_version: 'Python 3.12.0',
      ocamlc_version: '5.2.1',
      ocamlopt_version: '5.2.1',
      dune_version: '3.15.3'
    },
    bootstrap_snapshot: {
      path: 'packages/hxhx/bootstrap_out',
      sha256: 'b'.repeat(64),
      file_count: 10,
      byte_count: 1000
    },
    config: {
      reps: 2,
      dune_jobs: 'auto',
      dune_cache_storage_mode: 'auto',
      lane_order: laneOrder,
      lanes: JSON.parse(JSON.stringify(laneDefinitions)),
      private_cache_prime_completed: true
    },
    measurement: JSON.parse(JSON.stringify(measurementContract)),
    runs,
    summaries,
    comparison: buildComparison(summaries)
  }
}

function fileEvidence(filePath, tmpDir) {
  return {
    path: path.relative(tmpDir, filePath).split(path.sep).join('/'),
    sha256: crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex'),
    size_bytes: fs.statSync(filePath).size
  }
}

function materializeEvidence(report, tmpDir) {
  const artifactPath = path.join(tmpDir, 'artifacts/hxhx-fixture.exe')
  fs.mkdirSync(path.dirname(artifactPath), { recursive: true })
  fs.writeFileSync(artifactPath, 'fixture native executable\n')
  for (const run of report.runs) {
    const resourcePath = path.join(tmpDir, run.resource.path)
    const stdoutPath = path.join(tmpDir, run.stdout.path)
    const stderrPath = path.join(tmpDir, run.stderr.path)
    const smokePath = path.join(tmpDir, run.smoke.path)
    fs.mkdirSync(path.dirname(resourcePath), { recursive: true })
    const resource = {
      schema: resourceSchema,
      label: `${run.lane}.${run.rep}`,
      command: buildCommand,
      started_at: '2026-07-14T00:00:00.000Z',
      ended_at: '2026-07-14T00:00:01.000Z',
      elapsed_ms: run.elapsed_ms,
      peak_child_rss_kb: run.peak_child_rss_kb,
      rss_scope: resourceScope,
      exit_code: 0,
      launch_error: null
    }
    fs.writeFileSync(resourcePath, `${JSON.stringify(resource, null, 2)}\n`)
    fs.writeFileSync(stdoutPath, '/tmp/fixture/out.exe\n')
    fs.writeFileSync(stderrPath, '')
    fs.writeFileSync(smokePath, `${requiredSmokeTargets.join('\n')}\n`)
    run.resource = fileEvidence(resourcePath, tmpDir)
    run.stdout = fileEvidence(stdoutPath, tmpDir)
    run.stderr = fileEvidence(stderrPath, tmpDir)
    run.artifact = {
      ...fileEvidence(artifactPath, tmpDir),
      kind: run.artifact.kind
    }
    run.smoke = {
      ...fileEvidence(smokePath, tmpDir),
      required_targets: requiredSmokeTargets
    }
  }
}

function runValidator(report, expectedStatus, label, tmpDir, options = {}) {
  materializeEvidence(report, tmpDir)
  const firstRun = report.runs[0]
  const firstResource = path.join(tmpDir, firstRun?.resource?.path || '')
  const firstArtifact = path.join(tmpDir, firstRun?.artifact?.path || '')
  const firstSmoke = path.join(tmpDir, firstRun?.smoke?.path || '')
  if (options.rewriteResource && fs.existsSync(firstResource)) {
    const resource = JSON.parse(fs.readFileSync(firstResource, 'utf8'))
    options.rewriteResource(resource)
    fs.writeFileSync(firstResource, `${JSON.stringify(resource, null, 2)}\n`)
    firstRun.resource = fileEvidence(firstResource, tmpDir)
  }
  if (options.tamperResource && fs.existsSync(firstResource)) fs.appendFileSync(firstResource, 'tampered\n')
  if (options.removeResource && fs.existsSync(firstResource)) fs.rmSync(firstResource)
  if (options.tamperArtifact && fs.existsSync(firstArtifact)) fs.appendFileSync(firstArtifact, 'tampered\n')
  if (options.removeArtifact && fs.existsSync(firstArtifact)) fs.rmSync(firstArtifact)
  if (options.tamperSmoke && fs.existsSync(firstSmoke)) fs.writeFileSync(firstSmoke, 'js\n')
  if (options.removeSmoke && fs.existsSync(firstSmoke)) fs.rmSync(firstSmoke)
  const reportPath = path.join(tmpDir, `${label}.json`)
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
  const result = childProcess.spawnSync(process.execPath, [validator, 'validate', '--report', reportPath], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== expectedStatus) {
    fail(`${label}: expected status ${expectedStatus}, received ${result.status}\n${result.stdout}\n${result.stderr}`)
  }
  if (expectedStatus === 0 && !result.stdout.includes(passMarker)) {
    fail(`${label}: valid fixture did not emit ${passMarker}`)
  }
}

function testResourceHelper(tmpDir) {
  const helperDir = path.join(tmpDir, 'resource-helper')
  fs.mkdirSync(helperDir, { recursive: true })
  const successReport = path.join(helperDir, 'success.json')
  const success = childProcess.spawnSync('python3', [
    resourceHelper,
    '--cwd', repoRoot,
    '--stdout', path.join(helperDir, 'success.stdout'),
    '--stderr', path.join(helperDir, 'success.stderr'),
    '--json-out', successReport,
    '--label', 'fixture-success',
    '--', process.execPath, '-e', 'process.stdout.write("ok")'
  ], { cwd: repoRoot, encoding: 'utf8' })
  if (success.status !== 0) fail(`resource helper success fixture failed: ${success.stderr}`)
  const successPayload = JSON.parse(fs.readFileSync(successReport, 'utf8'))
  if (successPayload.schema !== resourceSchema || successPayload.exit_code !== 0) {
    fail('resource helper success report is malformed')
  }
  if (successPayload.rss_scope !== resourceScope || successPayload.peak_child_rss_kb < 0) {
    fail('resource helper did not state or record its memory scope')
  }

  const failureReport = path.join(helperDir, 'failure.json')
  const failure = childProcess.spawnSync('python3', [
    resourceHelper,
    '--cwd', repoRoot,
    '--stdout', path.join(helperDir, 'failure.stdout'),
    '--stderr', path.join(helperDir, 'failure.stderr'),
    '--json-out', failureReport,
    '--label', 'fixture-failure',
    '--', process.execPath, '-e', 'process.exit(7)'
  ], { cwd: repoRoot, encoding: 'utf8' })
  if (failure.status !== 7) fail(`resource helper must preserve command exit 7, received ${failure.status}`)
  const failurePayload = JSON.parse(fs.readFileSync(failureReport, 'utf8'))
  if (failurePayload.exit_code !== 7) fail('resource helper failure report did not preserve exit 7')
}

function main() {
  const runnerSource = fs.readFileSync(runner, 'utf8')
  for (const token of [
    'HXHX_STAGE0_FREE_BUILD_REPS:-3',
    'HXHX_FORBID_STAGE0=1',
    'HXHX_FORCE_STAGE0=0',
    'HXHX_BOOTSTRAP_PREFER_NATIVE=1',
    'HXHX_STAGE0_OCAML_BUILD=native',
    'DUNE_CACHE="$cache_mode"',
    'cache-disabled',
    'cache-primed',
    '--hxhx-list-targets'
  ]) {
    if (!runnerSource.includes(token)) fail(`runner is missing required build-proof token: ${token}`)
  }
  if (runnerSource.includes('MIN_SPEEDUP') || runnerSource.includes('minimum speedup')) {
    fail('stage0-free build benchmark must remain report-only until repeated evidence supports a threshold')
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-stage0-free-build-report-fixtures-'))
  try {
    testResourceHelper(tmpDir)
    runValidator(validReport(), 0, 'valid', tmpDir)
    const cases = [
      ['bad-schema', report => { report.schema = 'legacy' }],
      ['missing-recorded-at', report => { delete report.recorded_at }],
      ['missing-cpu', report => { delete report.environment.cpu_model }],
      ['bad-snapshot-digest', report => { report.bootstrap_snapshot.sha256 = 'bad' }],
      ['bad-cache-storage-mode', report => { report.config.dune_cache_storage_mode = 'mystery' }],
      ['bad-dune-jobs', report => { report.config.dune_jobs = 'many' }],
      ['changed-lane-contract', report => { report.config.lanes['cache-primed'].prime_runs = 0 }],
      ['missing-run', report => { report.runs.pop() }],
      ['duplicate-lane-rep', report => { report.runs[3].rep = 1 }],
      ['biased-lane-order', report => { report.runs[0].order = 2 }],
      ['bytecode-artifact', report => { report.runs[0].artifact.kind = 'ocaml-bytecode' }],
      ['cross-commit-artifact', report => { report.runs[0].artifact_commit = 'f'.repeat(40) }],
      ['stage0-not-forbidden', report => { report.runs[0].stage0_forbidden = false }],
      ['missing-memory-sample', report => { report.runs[0].peak_child_rss_kb = 0 }],
      ['summary-mismatch', report => { report.summaries[0].elapsed_ms.median = 1 }],
      ['comparison-mismatch', report => { report.comparison.primed_over_disabled_elapsed = 99 }],
      ['changed-measurement', report => { report.measurement.upstream_haxe_used_by_build = true }],
      ['release-looking-evidence', report => { report.evidence_level = 'release' }]
    ]
    for (const [label, mutate] of cases) {
      const report = validReport()
      mutate(report)
      runValidator(report, 1, label, tmpDir)
    }
    runValidator(validReport(), 1, 'wrong-resource-command', tmpDir, {
      rewriteResource: resource => { resource.command = ['haxe', 'build.hxml'] }
    })
    runValidator(validReport(), 1, 'failed-resource', tmpDir, {
      rewriteResource: resource => { resource.exit_code = 1 }
    })
    runValidator(validReport(), 1, 'tampered-resource', tmpDir, { tamperResource: true })
    runValidator(validReport(), 1, 'missing-resource', tmpDir, { removeResource: true })
    runValidator(validReport(), 1, 'tampered-artifact', tmpDir, { tamperArtifact: true })
    runValidator(validReport(), 1, 'missing-artifact', tmpDir, { removeArtifact: true })
    runValidator(validReport(), 1, 'tampered-smoke', tmpDir, { tamperSmoke: true })
    runValidator(validReport(), 1, 'missing-smoke', tmpDir, { removeSmoke: true })
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
  console.log('[ci:guards] OK: stage0-free build benchmark report fixtures pass')
}

main()
