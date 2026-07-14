#!/usr/bin/env node

/**
 * Synthetic contract tests for self-describing Full1 phase-timing artifacts.
 * These fixtures prove report validation; they are not performance evidence.
 */

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const script = path.join(root, 'scripts/ci/full1-phase-timing.js')
const {
  absoluteStringLocations,
  passMarker,
  recordSchema,
  summarySchema,
  validateSummary
} = require(script)

const commit = '0123456789abcdef0123456789abcdef01234567'
const otherCommit = 'f'.repeat(40)

function fail(message) {
  console.error(`[full1-phase-timing-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function runCli(args, environment, expectedStatus = 0) {
  const result = childProcess.spawnSync(process.execPath, [script, ...args], {
    cwd: root,
    env: environment,
    encoding: 'utf8'
  })
  if (result.status !== expectedStatus) {
    fail(`${args.join(' ')} expected status ${expectedStatus}, received ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  return result
}

function cleanGitHubEnvironment() {
  return {
    ...process.env,
    GITHUB_SHA: '',
    GITHUB_RUN_ID: '',
    GITHUB_RUN_ATTEMPT: '',
    GITHUB_REPOSITORY: '',
    GITHUB_EVENT_NAME: '',
    GITHUB_WORKFLOW: '',
    GITHUB_WORKFLOW_REF: '',
    GITHUB_WORKFLOW_SHA: '',
    GITHUB_JOB: '',
    RUNNER_NAME: ''
  }
}

function githubEnvironment() {
  return {
    ...cleanGitHubEnvironment(),
    GITHUB_SHA: commit,
    GITHUB_RUN_ID: '123456789',
    GITHUB_RUN_ATTEMPT: '2',
    GITHUB_REPOSITORY: 'fullofcaffeine/hxhx',
    GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_WORKFLOW: 'Full1 fixture workflow',
    GITHUB_WORKFLOW_REF: 'fullofcaffeine/hxhx/.github/workflows/fixture.yml@refs/heads/main',
    GITHUB_WORKFLOW_SHA: commit,
    GITHUB_JOB: 'fixture_job',
    RUNNER_NAME: 'GitHub Actions fixture runner'
  }
}

function provenanceArgs() {
  return [
    '--recorded-at', '2026-07-14T04:00:00.000Z',
    '--tracked-source-clean', 'true',
    '--os', 'Linux',
    '--architecture', 'x64',
    '--cpu-model', 'Fixture CPU',
    '--node-version', 'v20.20.2',
    '--haxe-version', '4.3.7',
    '--python-version', 'Python 3.12.3',
    '--ocamlc-version', '5.2.1',
    '--ocamlopt-version', '5.2.1',
    '--dune-version', '3.24.0'
  ]
}

function appendFixturePhases(jsonl, environment, runArgs = []) {
  runCli([
    'append',
    '--jsonl', jsonl,
    '--commit', commit,
    ...runArgs,
    '--workflow', 'full1-fixture',
    '--job', 'build_hxhx',
    '--phase', 'prepare_dependencies',
    '--started-ms', '1000',
    '--ended-ms', '2500',
    '--status', 'pass',
    '--exit-code', '0'
  ], environment)
  runCli([
    'append',
    '--jsonl', jsonl,
    '--commit', commit,
    ...runArgs,
    '--workflow', 'full1-fixture',
    '--job', 'build_hxhx',
    '--phase', 'build_native_hxhx',
    '--started-ms', '3000',
    '--ended-ms', '5500',
    '--status', 'pass',
    '--exit-code', '0',
    '--detail', 'fixture=native'
  ], environment)
}

function buildFixtureReport(tmpDir, name, environment, runArgs = []) {
  const fixtureDir = path.join(tmpDir, name)
  const jsonl = path.join(fixtureDir, 'timings.jsonl')
  const jsonOut = path.join(fixtureDir, 'timings.summary.json')
  const markdownOut = path.join(fixtureDir, 'timings.md')
  appendFixturePhases(jsonl, environment, runArgs)
  runCli([
    'summarize',
    '--jsonl', jsonl,
    '--json-out', jsonOut,
    '--markdown-out', markdownOut,
    '--commit', commit,
    ...runArgs,
    ...provenanceArgs()
  ], environment)
  const validation = runCli([
    'validate',
    '--report', jsonOut,
    '--expected-commit', commit
  ], environment)
  if (!validation.stdout.includes(passMarker)) fail(`${name} did not emit ${passMarker}`)
  return {
    report: JSON.parse(fs.readFileSync(jsonOut, 'utf8')),
    markdown: fs.readFileSync(markdownOut, 'utf8'),
    jsonOut
  }
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function expectInvalid(base, label, mutate, expectedText) {
  const report = clone(base)
  mutate(report)
  const errors = validateSummary(report)
  if (errors.length === 0) fail(`${label}: validator accepted invalid report`)
  if (expectedText && !errors.some(error => error.includes(expectedText))) {
    fail(`${label}: expected error containing ${expectedText}; received ${errors.join(' | ')}`)
  }
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-phase-timing-fixtures-'))
  try {
    const github = buildFixtureReport(tmpDir, 'github', githubEnvironment())
    if (github.report.schema !== summarySchema) fail('GitHub fixture summary schema mismatch')
    if (github.report.phases.some(phase => phase.schema !== recordSchema)) fail('GitHub fixture record schema mismatch')
    if (github.report.git.commit !== commit || github.report.git.tracked_source_clean_at_summary !== true) {
      fail('GitHub fixture is missing exact commit/clean-state provenance')
    }
    if (github.report.ci.provider !== 'github-actions'
        || github.report.ci.run_id !== '123456789'
        || github.report.ci.run_attempt !== '2') {
      fail('GitHub fixture is missing run provenance')
    }
    if (github.report.total_measured_phase_duration_ms !== 4000 || github.report.phase_count !== 2) {
      fail('GitHub fixture summary does not match raw phases')
    }
    if (absoluteStringLocations(github.report).length !== 0) fail('GitHub fixture contains an absolute path')
    for (const text of ['Commit:', 'GitHub Actions fixture runner', 'recorded phases only', 'diagnostic / report-only']) {
      if (!github.markdown.includes(text)) fail(`GitHub Markdown is missing: ${text}`)
    }

    const localRunArgs = ['--run-id', 'local', '--run-attempt', 'local']
    const local = buildFixtureReport(tmpDir, 'local', cleanGitHubEnvironment(), localRunArgs)
    if (local.report.ci.provider !== 'local'
        || local.report.ci.run_id !== 'local'
        || local.report.ci.run_attempt !== 'local') {
      fail('local fixture does not identify itself as local evidence')
    }

    const unavailableTools = clone(local.report)
    for (const key of ['haxe_version', 'python_version', 'ocamlc_version', 'ocamlopt_version', 'dune_version']) {
      unavailableTools.environment[key] = 'unavailable'
    }
    const unavailableErrors = validateSummary(unavailableTools)
    if (unavailableErrors.length > 0) fail(`explicit unavailable tool versions must remain valid: ${unavailableErrors.join(' | ')}`)

    const cases = [
      ['old-schema', report => { report.schema = 'full1-phase-timing-summary.v1' }, 'schema'],
      ['missing-recorded-at', report => { delete report.recorded_at }, 'recorded_at'],
      ['bad-summary-commit', report => { report.git.commit = 'bad' }, 'git.commit'],
      ['cross-commit-phase', report => { report.phases[0].git_commit = otherCommit }, 'commit does not match summary'],
      ['cross-run-phase', report => { report.phases[0].run_id = '999' }, 'run identity does not match summary'],
      ['wrong-workflow-phase', report => { report.phases[0].workflow = 'other' }, 'workflow/job does not match summary'],
      ['bad-start-timestamp', report => { report.phases[0].started_at = 'not-a-time' }, 'started_at'],
      ['duration-mismatch', report => { report.phases[0].duration_ms = 1 }, 'duration_ms does not match timestamps'],
      ['pass-with-failure-exit', report => { report.phases[0].exit_code = 1 }, 'pass status requires exit code 0'],
      ['summary-total-mismatch', report => { report.total_measured_phase_duration_ms = 1 }, 'total measured duration'],
      ['failed-count-mismatch', report => { report.failed_phase_count = 1 }, 'failed_phase_count'],
      ['absolute-source-path', report => { report.measurement.phase_source = '/tmp/timings.jsonl' }, 'phase_source'],
      ['missing-cpu', report => { delete report.environment.cpu_model }, 'environment.cpu_model'],
      ['missing-tool-version', report => { delete report.environment.haxe_version }, 'environment.haxe_version'],
      ['bad-workflow-sha', report => { report.ci.workflow_sha = 'bad' }, 'ci.workflow_sha'],
      ['github-with-local-run', report => { report.ci.run_id = 'local'; report.ci.run_attempt = 'local' }, 'GitHub reports'],
      ['release-looking-evidence', report => { report.evidence_level = 'release' }, 'evidence_level'],
      ['absolute-detail', report => { report.phases[1].detail = ['', 'Users', 'example', 'work'].join('/') }, 'absolute machine-local path']
    ]
    for (const [label, mutate, expectedText] of cases) expectInvalid(github.report, label, mutate, expectedText)

    const wrongExpected = runCli([
      'validate',
      '--report', github.jsonOut,
      '--expected-commit', otherCommit
    ], githubEnvironment(), 1)
    if (!wrongExpected.stderr.includes('does not match expected commit')) {
      fail('CLI validator did not explain the expected-commit mismatch')
    }

    const badAppend = runCli([
      'append',
      '--jsonl', path.join(tmpDir, 'bad.jsonl'),
      '--commit', commit,
      '--run-id', 'local',
      '--run-attempt', 'local',
      '--workflow', 'fixture',
      '--job', 'fixture',
      '--phase', 'backwards',
      '--started-ms', '2000',
      '--ended-ms', '1000',
      '--status', 'pass',
      '--exit-code', '0'
    ], cleanGitHubEnvironment(), 1)
    if (!badAppend.stderr.includes('must not precede')) fail('append did not reject backwards timestamps')

    const mismatchedCheckout = runCli([
      'append',
      '--jsonl', path.join(tmpDir, 'mismatched-checkout.jsonl'),
      '--workflow', 'fixture',
      '--job', 'fixture',
      '--phase', 'candidate_check',
      '--started-ms', '1000',
      '--ended-ms', '2000',
      '--status', 'pass',
      '--exit-code', '0'
    ], githubEnvironment(), 1)
    if (!mismatchedCheckout.stderr.includes('does not match checked-out commit')) {
      fail('append did not reject a GitHub candidate/check-out mismatch')
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
  console.log('[ci:guards] OK: Full1 phase timing v2 fixtures pass')
}

main()
