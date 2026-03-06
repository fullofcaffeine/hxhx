#!/usr/bin/env node
/**
 * full1-bootstrap-source-reconcile.js
 *
 * Full1 diagnostic reconciliation lane:
 * - Run strict suite checks with bootstrap-built hxhx.
 * - Run strict suite checks with source-built hxhx (HXHX_FORCE_STAGE0=1).
 * - Classify per-suite outcomes to separate bootstrap lag from real parity bugs.
 *
 * The script is evidence-oriented. It only emits PASS when classification data is
 * complete for the blocker suites (server + optimization by default).
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const DEFAULT_SUITES = ['server', 'optimization']
const BLOCKER_SUITES = new Set(['server', 'optimization'])

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    artifactsDir: '.artifacts/full1/reconciliation',
    suites: DEFAULT_SUITES.slice(),
    bootstrapHxhxBin: '',
    sourceHxhxBin: '',
    buildTimeoutSecs: Math.max(1, parseInt(process.env.FULL1_RECONCILE_BUILD_TIMEOUT_SECS || '900', 10) || 900),
    suiteTimeoutSecs: Math.max(1, parseInt(process.env.FULL1_RECONCILE_SUITE_TIMEOUT_SECS || '600', 10) || 600),
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--root') {
      out.root = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--artifacts-dir') {
      out.artifactsDir = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--suites') {
      const raw = String(argv[i + 1] || '').trim()
      i += 1
      out.suites = raw.length === 0
        ? []
        : raw
          .split(',')
          .map((v) => v.trim().toLowerCase())
          .filter((v) => v.length > 0)
      continue
    }
    if (arg === '--bootstrap-hxhx-bin') {
      out.bootstrapHxhxBin = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--source-hxhx-bin') {
      out.sourceHxhxBin = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--build-timeout-secs') {
      out.buildTimeoutSecs = Math.max(1, parseInt(String(argv[i + 1] || '').trim(), 10) || out.buildTimeoutSecs)
      i += 1
      continue
    }
    if (arg === '--suite-timeout-secs') {
      out.suiteTimeoutSecs = Math.max(1, parseInt(String(argv[i + 1] || '').trim(), 10) || out.suiteTimeoutSecs)
      i += 1
      continue
    }
    throw new Error(`unknown argument: ${arg}`)
  }

  if (out.suites.length === 0) {
    throw new Error('no suites selected')
  }

  out.root = path.resolve(out.root)
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  out.bootstrapArtifactsDir = path.join(out.artifactsDir, 'bootstrap')
  out.sourceArtifactsDir = path.join(out.artifactsDir, 'source')
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function run(command, args, options) {
  return cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64,
    timeout: options.timeoutMs,
  })
}

function getCommitSha(root) {
  const result = run('git', ['rev-parse', 'HEAD'], { cwd: root, env: process.env })
  if (result.status !== 0) {
    return ''
  }
  return String(result.stdout || '').trim()
}

function parseBuildBinaryPath(stdoutText) {
  const lines = String(stdoutText || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
  if (lines.length === 0) {
    return ''
  }
  const candidate = lines[lines.length - 1]
  if (candidate.startsWith('== ')) {
    return ''
  }
  return candidate
}

function resolveProvidedBinary(root, providedPath) {
  if (!providedPath) {
    return ''
  }
  const resolved = path.resolve(root, providedPath)
  if (!fs.existsSync(resolved)) {
    throw new Error(`provided binary does not exist: ${resolved}`)
  }
  return resolved
}

function buildHxhx(root, env, providedBin, timeoutMs) {
  if (providedBin) {
    return {
      mode: 'provided',
      exit_code: 0,
      hxhx_bin: resolveProvidedBinary(root, providedBin),
      stdout: '',
      stderr: '',
      error: '',
    }
  }

  const buildScript = path.join(root, 'scripts/hxhx/build-hxhx.sh')
  const result = run('bash', [buildScript], { cwd: root, env, timeoutMs })
  const out = {
    mode: 'built',
    exit_code: result.status == null ? -1 : result.status,
    hxhx_bin: '',
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    error: result.error ? String(result.error.message || result.error) : '',
    timed_out: Boolean(result.error && result.error.code === 'ETIMEDOUT'),
  }

  if (out.exit_code === 0) {
    const candidate = parseBuildBinaryPath(out.stdout)
    if (candidate.length > 0) {
      const resolved = path.resolve(root, candidate)
      if (fs.existsSync(resolved)) {
        out.hxhx_bin = resolved
      }
    }
  }
  return out
}

function runSuite(root, suite, hxhxBin, artifactsDir, env, timeoutMs) {
  const summaryPath = path.join(artifactsDir, `${suite}.summary.json`)
  const logPath = path.join(artifactsDir, `${suite}.log`)
  const startedAt = new Date()
  const result = run(
    'node',
    [
      path.join(root, 'scripts/ci/run-upstream-suite.js'),
      '--suite',
      suite,
      '--strict',
      '--hxhx-bin',
      hxhxBin,
      '--artifacts-dir',
      artifactsDir,
    ],
    { cwd: root, env, timeoutMs }
  )
  const endedAt = new Date()

  let parsedSummary = null
  if (fs.existsSync(summaryPath)) {
    try {
      parsedSummary = JSON.parse(fs.readFileSync(summaryPath, 'utf8'))
    } catch (_) {
      parsedSummary = null
    }
  }

  return {
    suite,
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: endedAt.getTime() - startedAt.getTime(),
    exit_code: result.status == null ? -1 : result.status,
    signal: result.signal || '',
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    error: result.error ? String(result.error.message || result.error) : '',
    timed_out: Boolean(result.error && result.error.code === 'ETIMEDOUT'),
    summary_path: summaryPath,
    log_path: logPath,
    summary: parsedSummary,
  }
}

function readLogSnippet(logPath) {
  if (!fs.existsSync(logPath)) {
    return ''
  }
  const text = String(fs.readFileSync(logPath, 'utf8') || '')
  const patterns = [
    /\[js-native:[^\]]+\][^\n]*/i,
    /body_parse_error[^\n]*/i,
    /unsupported_expr[^\n]*/i,
    /ENew[^\n]*/i,
    /No target selected[^\n]*/i,
    /stage0 forbidden[^\n]*/i,
    /suite=.*failed[^\n]*/i,
  ]
  for (const pattern of patterns) {
    const match = text.match(pattern)
    if (match && match[0]) {
      return match[0].trim()
    }
  }

  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
  return lines.length > 0 ? lines[0] : ''
}

function laneStatus(runItem) {
  const exitCode = runItem && runItem.summary && typeof runItem.summary.exit_code === 'number'
    ? runItem.summary.exit_code
    : runItem.exit_code
  return exitCode === 0 ? 'pass' : 'fail'
}

function classifySuite(suite, bootstrapRun, sourceRun, sourceBuild) {
  const bootstrapHasSummary = Boolean(bootstrapRun && bootstrapRun.summary)
  const sourceHasSummary = Boolean(sourceRun && sourceRun.summary)
  const bootstrapStatus = bootstrapHasSummary ? laneStatus(bootstrapRun) : 'missing'
  const sourceStatus = sourceHasSummary ? laneStatus(sourceRun) : 'missing'

  const bootstrapSignature = bootstrapRun ? readLogSnippet(bootstrapRun.log_path) : ''
  const sourceSignature = sourceRun ? readLogSnippet(sourceRun.log_path) : ''

  let classification = 'unknown'
  let rationale = ''
  let recommendedAction = ''

  if (!sourceBuild || sourceBuild.exit_code !== 0 || !sourceBuild.hxhx_bin) {
    classification = 'source-build-instability'
    rationale = sourceBuild && sourceBuild.timed_out
      ? 'Source hxhx build hit the reconciliation timeout before producing a binary.'
      : 'Source hxhx build failed or produced no binary path.'
    recommendedAction = 'Inspect source lane build logs and stabilize scripts/hxhx/build-hxhx.sh before using probe evidence for parity closure.'
  } else if (sourceRun && sourceRun.timed_out) {
    classification = 'source-build-instability'
    rationale = 'Source suite execution hit the reconciliation timeout before writing a complete summary.'
    recommendedAction = 'Increase timeout only if progress is real; otherwise fix the long-tail source suite path before using reconciliation evidence.'
  } else if (bootstrapRun && bootstrapRun.timed_out) {
    classification = 'bootstrap-instability'
    rationale = 'Bootstrap suite execution hit the reconciliation timeout before writing a complete summary.'
    recommendedAction = 'Stabilize or bound the bootstrap lane before using it as the comparison baseline for this blocker.'
  } else if (!bootstrapHasSummary || !sourceHasSummary) {
    classification = 'unknown'
    rationale = 'Missing suite summary artifact for bootstrap or source lane.'
    recommendedAction = 'Re-run reconciliation lane and ensure both bootstrap and source suite summaries are written.'
  } else if (bootstrapStatus === 'fail' && sourceStatus === 'pass') {
    classification = 'source-fixed-bootstrap-lag'
    rationale = 'Bootstrap lane fails while source-built lane passes on the same commit.'
    recommendedAction = 'Refresh bootstrap snapshots (regen/build) and re-run bootstrap-based Full1 suite matrix to propagate the source fix.'
  } else if (bootstrapStatus === 'pass' && sourceStatus === 'pass') {
    classification = 'in-sync-pass'
    rationale = 'Both lanes pass for this suite on the same commit.'
    recommendedAction = 'No action required.'
  } else if (sourceStatus === 'fail' && sourceRun && sourceRun.error) {
    classification = 'source-build-instability'
    rationale = 'Source suite run failed with runner/runtime execution error.'
    recommendedAction = 'Stabilize source suite execution path (macro host/build/runtime) and rerun reconciliation.'
  } else {
    classification = 'real-parity-bug'
    rationale = 'Suite fails under source-built lane; failure is not explained by bootstrap lag.'
    recommendedAction = 'Keep parity blocker open and fix compiler/runtime behavior for this suite.'
  }

  return {
    suite,
    classification,
    rationale,
    recommended_action: recommendedAction,
    bootstrap: {
      status: bootstrapStatus,
      exit_code: bootstrapHasSummary ? bootstrapRun.summary.exit_code : bootstrapRun ? bootstrapRun.exit_code : -1,
      summary_path: bootstrapRun ? bootstrapRun.summary_path : '',
      signature: bootstrapSignature,
    },
    source: {
      status: sourceStatus,
      exit_code: sourceHasSummary ? sourceRun.summary.exit_code : sourceRun ? sourceRun.exit_code : -1,
      summary_path: sourceRun ? sourceRun.summary_path : '',
      signature: sourceSignature,
    },
  }
}

function main() {
  const startedAt = new Date()
  let parsed
  try {
    parsed = parseArgs(process.argv.slice(2))
  } catch (error) {
    console.error(`[full1-reconcile] ERROR: ${String(error && error.message ? error.message : error)}`)
    process.exit(2)
  }

  ensureDir(parsed.artifactsDir)
  ensureDir(parsed.bootstrapArtifactsDir)
  ensureDir(parsed.sourceArtifactsDir)

  const commitSha = getCommitSha(parsed.root)
  const summary = {
    schema: 'full1-bootstrap-source-reconciliation.v1',
    started_at: startedAt.toISOString(),
    root: parsed.root,
    commit_sha: commitSha,
    suites: parsed.suites,
    lanes: {
      bootstrap: {
        artifacts_dir: parsed.bootstrapArtifactsDir,
      },
      source: {
        artifacts_dir: parsed.sourceArtifactsDir,
      },
    },
    timeouts: {
      build_timeout_secs: parsed.buildTimeoutSecs,
      suite_timeout_secs: parsed.suiteTimeoutSecs,
    },
    suite_classifications: [],
    blocker_classifications: [],
    marker: 'FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:WARN',
    status: 'warn',
  }

  const bootstrapEnv = { ...process.env }
  delete bootstrapEnv.HXHX_FORCE_STAGE0

  const sourceEnv = { ...process.env }
  sourceEnv.HXHX_FORCE_STAGE0 = sourceEnv.HXHX_FORCE_STAGE0 || '1'
  sourceEnv.HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS = sourceEnv.HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS || '900'
  sourceEnv.HXHX_STAGE0_CONNECT_IDLE_SECS = sourceEnv.HXHX_STAGE0_CONNECT_IDLE_SECS || '45'

  let bootstrapBuild
  try {
    bootstrapBuild = buildHxhx(parsed.root, bootstrapEnv, parsed.bootstrapHxhxBin, parsed.buildTimeoutSecs * 1000)
  } catch (error) {
    bootstrapBuild = {
      mode: 'provided',
      exit_code: -1,
      hxhx_bin: '',
      stdout: '',
      stderr: '',
      error: String(error && error.message ? error.message : error),
    }
  }
  summary.lanes.bootstrap.build = bootstrapBuild

  let sourceBuild
  try {
    sourceBuild = buildHxhx(parsed.root, sourceEnv, parsed.sourceHxhxBin, parsed.buildTimeoutSecs * 1000)
  } catch (error) {
    sourceBuild = {
      mode: 'provided',
      exit_code: -1,
      hxhx_bin: '',
      stdout: '',
      stderr: '',
      error: String(error && error.message ? error.message : error),
    }
  }
  summary.lanes.source.build = sourceBuild

  const bootstrapSuiteRuns = {}
  if (bootstrapBuild.exit_code === 0 && bootstrapBuild.hxhx_bin) {
    for (const suite of parsed.suites) {
      bootstrapSuiteRuns[suite] = runSuite(
        parsed.root,
        suite,
        bootstrapBuild.hxhx_bin,
        parsed.bootstrapArtifactsDir,
        bootstrapEnv,
        parsed.suiteTimeoutSecs * 1000
      )
    }
  }

  const sourceSuiteRuns = {}
  if (sourceBuild.exit_code === 0 && sourceBuild.hxhx_bin) {
    for (const suite of parsed.suites) {
      sourceSuiteRuns[suite] = runSuite(
        parsed.root,
        suite,
        sourceBuild.hxhx_bin,
        parsed.sourceArtifactsDir,
        sourceEnv,
        parsed.suiteTimeoutSecs * 1000
      )
    }
  }

  for (const suite of parsed.suites) {
    const classification = classifySuite(
      suite,
      bootstrapSuiteRuns[suite],
      sourceSuiteRuns[suite],
      sourceBuild
    )
    summary.suite_classifications.push(classification)
    if (BLOCKER_SUITES.has(suite)) {
      summary.blocker_classifications.push(classification)
    }
  }

  const blockersClassified = summary.blocker_classifications.length > 0
    && summary.blocker_classifications.every((item) => item.classification !== 'unknown')

  if (blockersClassified) {
    summary.status = 'pass'
    summary.marker = 'FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:PASS'
  } else {
    summary.status = 'warn'
    summary.marker = 'FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:WARN'
  }

  const endedAt = new Date()
  summary.ended_at = endedAt.toISOString()
  summary.duration_ms = endedAt.getTime() - startedAt.getTime()

  const summaryPath = path.join(parsed.artifactsDir, 'bootstrap-source-reconciliation.summary.json')
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8')

  console.log(`[full1-reconcile] summary=${summaryPath}`)
  console.log(summary.marker)
}

main()
