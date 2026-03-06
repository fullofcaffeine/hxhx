#!/usr/bin/env node
/**
 * full1-bootstrap-source-reconcile.js
 *
 * Full1 diagnostic reconciliation lane tooling.
 *
 * Modes:
 * - full: run bootstrap build, source build, both blocker suites, then classify.
 * - build: build one lane and stage the resulting hxhx binary into artifacts.
 * - suite: run one suite for one lane using a provided hxhx binary.
 * - classify: classify existing build/suite artifacts into a single summary.
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const DEFAULT_SUITES = ['server', 'optimization']
const BLOCKER_SUITES = new Set(['server', 'optimization'])
const VALID_MODES = new Set(['full', 'build', 'suite', 'classify'])
const VALID_LANES = new Set(['bootstrap', 'source'])

function parseArgs(argv) {
  const out = {
    mode: 'full',
    root: process.cwd(),
    artifactsDir: '.artifacts/full1/reconciliation',
    suites: DEFAULT_SUITES.slice(),
    bootstrapHxhxBin: '',
    sourceHxhxBin: '',
    buildTimeoutSecs: Math.max(1, parseInt(process.env.FULL1_RECONCILE_BUILD_TIMEOUT_SECS || '900', 10) || 900),
    suiteTimeoutSecs: Math.max(1, parseInt(process.env.FULL1_RECONCILE_SUITE_TIMEOUT_SECS || '600', 10) || 600),
    lane: '',
    suite: '',
    hxhxBin: '',
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--mode') {
      out.mode = String(argv[i + 1] || '').trim().toLowerCase()
      i += 1
      continue
    }
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
    if (arg === '--lane') {
      out.lane = String(argv[i + 1] || '').trim().toLowerCase()
      i += 1
      continue
    }
    if (arg === '--suite') {
      out.suite = String(argv[i + 1] || '').trim().toLowerCase()
      i += 1
      continue
    }
    if (arg === '--hxhx-bin') {
      out.hxhxBin = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    throw new Error(`unknown argument: ${arg}`)
  }

  if (!VALID_MODES.has(out.mode)) {
    throw new Error(`invalid mode: ${out.mode}`)
  }
  if (out.suites.length === 0) {
    throw new Error('no suites selected')
  }

  out.root = path.resolve(out.root)
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  out.bootstrapArtifactsDir = path.join(out.artifactsDir, 'bootstrap')
  out.sourceArtifactsDir = path.join(out.artifactsDir, 'source')

  if (out.mode === 'build' || out.mode === 'suite') {
    if (!VALID_LANES.has(out.lane)) {
      throw new Error(`mode ${out.mode} requires --lane bootstrap|source`)
    }
  }
  if (out.mode === 'suite') {
    if (out.suite.length === 0) {
      throw new Error('mode suite requires --suite <name>')
    }
  }

  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8')
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    return null
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (_) {
    return null
  }
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

function laneArtifactsDir(parsed, lane) {
  return lane === 'source' ? parsed.sourceArtifactsDir : parsed.bootstrapArtifactsDir
}

function laneProvidedBinary(parsed, lane) {
  return lane === 'source' ? parsed.sourceHxhxBin : parsed.bootstrapHxhxBin
}

function laneEnv(lane) {
  const env = { ...process.env }
  if (lane === 'source') {
    env.HXHX_FORCE_STAGE0 = env.HXHX_FORCE_STAGE0 || '1'
    env.HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS = env.HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS || '900'
    env.HXHX_STAGE0_CONNECT_IDLE_SECS = env.HXHX_STAGE0_CONNECT_IDLE_SECS || '45'
  } else {
    delete env.HXHX_FORCE_STAGE0
  }
  return env
}

function stageBinary(stagedPath, sourcePath) {
  ensureDir(path.dirname(stagedPath))
  fs.copyFileSync(sourcePath, stagedPath)
  fs.chmodSync(stagedPath, 0o755)
  return stagedPath
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
      timed_out: false,
      artifact_hxhx_bin: '',
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
    artifact_hxhx_bin: '',
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

  return {
    suite,
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: endedAt.getTime() - startedAt.getTime(),
    exit_code: result.status == null ? -1 : result.status,
    signal: result.signal || '',
    error: result.error ? String(result.error.message || result.error) : '',
    timed_out: Boolean(result.error && result.error.code === 'ETIMEDOUT'),
    summary_path: summaryPath,
    log_path: logPath,
    summary: readJson(summaryPath),
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
    : runItem
      ? runItem.exit_code
      : -1
  return exitCode === 0 ? 'pass' : 'fail'
}

function hydrateRunItem(runPath, fallbackSummaryPath, fallbackLogPath) {
  const runItem = readJson(runPath)
  if (!runItem) {
    const summary = readJson(fallbackSummaryPath)
    if (!summary && !fs.existsSync(fallbackLogPath)) {
      return null
    }
    return {
      exit_code: summary && typeof summary.exit_code === 'number' ? summary.exit_code : -1,
      signal: '',
      error: '',
      timed_out: false,
      summary_path: fallbackSummaryPath,
      log_path: fallbackLogPath,
      summary,
    }
  }
  if (!runItem.summary && runItem.summary_path) {
    runItem.summary = readJson(runItem.summary_path)
  }
  return runItem
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

  if (!sourceBuild || sourceBuild.exit_code !== 0 || !sourceBuild.artifact_hxhx_bin) {
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

function createSummary(parsed, startedAt, commitSha) {
  return {
    schema: 'full1-bootstrap-source-reconciliation.v1',
    started_at: startedAt.toISOString(),
    root: parsed.root,
    commit_sha: commitSha,
    suites: parsed.suites,
    lanes: {
      bootstrap: { artifacts_dir: parsed.bootstrapArtifactsDir },
      source: { artifacts_dir: parsed.sourceArtifactsDir },
    },
    timeouts: {
      build_timeout_secs: parsed.buildTimeoutSecs,
      suite_timeout_secs: parsed.suiteTimeoutSecs,
    },
    suite_classifications: [],
    blocker_classifications: [],
    marker: 'FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:WARN',
    status: 'warn',
    current_phase: 'initializing',
  }
}

function finalizeSummary(summary, startedAt) {
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
  summary.current_phase = 'done'
}

function runBuildMode(parsed) {
  const laneDir = laneArtifactsDir(parsed, parsed.lane)
  ensureDir(parsed.artifactsDir)
  ensureDir(laneDir)
  const build = buildHxhx(parsed.root, laneEnv(parsed.lane), laneProvidedBinary(parsed, parsed.lane), parsed.buildTimeoutSecs * 1000)
  if (build.exit_code === 0 && build.hxhx_bin) {
    build.artifact_hxhx_bin = stageBinary(path.join(laneDir, 'hxhx'), build.hxhx_bin)
  }
  const summaryPath = path.join(laneDir, 'build.summary.json')
  writeJson(summaryPath, build)
  console.log(`[full1-reconcile] lane=${parsed.lane} build_summary=${summaryPath}`)
  if (build.artifact_hxhx_bin) {
    console.log(`[full1-reconcile] lane=${parsed.lane} hxhx_bin=${build.artifact_hxhx_bin}`)
  }
}

function runSuiteMode(parsed) {
  const laneDir = laneArtifactsDir(parsed, parsed.lane)
  ensureDir(parsed.artifactsDir)
  ensureDir(laneDir)
  const runPath = path.join(laneDir, `${parsed.suite}.run.json`)
  const resolvedBin = parsed.hxhxBin ? path.resolve(parsed.root, parsed.hxhxBin) : ''
  let runItem
  if (!resolvedBin || !fs.existsSync(resolvedBin)) {
    const now = new Date().toISOString()
    runItem = {
      suite: parsed.suite,
      started_at: now,
      ended_at: now,
      duration_ms: 0,
      exit_code: -1,
      signal: '',
      error: resolvedBin ? `missing hxhx binary: ${resolvedBin}` : 'missing hxhx binary path',
      timed_out: false,
      summary_path: path.join(laneDir, `${parsed.suite}.summary.json`),
      log_path: path.join(laneDir, `${parsed.suite}.log`),
      summary: readJson(path.join(laneDir, `${parsed.suite}.summary.json`)),
    }
  } else {
    fs.chmodSync(resolvedBin, 0o755)
    runItem = runSuite(parsed.root, parsed.suite, resolvedBin, laneDir, laneEnv(parsed.lane), parsed.suiteTimeoutSecs * 1000)
  }
  writeJson(runPath, runItem)
  console.log(`[full1-reconcile] lane=${parsed.lane} suite=${parsed.suite} run_summary=${runPath}`)
}

function runClassifyMode(parsed) {
  ensureDir(parsed.artifactsDir)
  const startedAt = new Date()
  const summaryPath = path.join(parsed.artifactsDir, 'bootstrap-source-reconciliation.summary.json')
  const summary = createSummary(parsed, startedAt, getCommitSha(parsed.root))
  summary.current_phase = 'classification'

  const bootstrapBuild = readJson(path.join(parsed.bootstrapArtifactsDir, 'build.summary.json'))
  const sourceBuild = readJson(path.join(parsed.sourceArtifactsDir, 'build.summary.json'))
  summary.lanes.bootstrap.build = bootstrapBuild || null
  summary.lanes.source.build = sourceBuild || null

  for (const suite of parsed.suites) {
    const bootstrapRun = hydrateRunItem(
      path.join(parsed.bootstrapArtifactsDir, `${suite}.run.json`),
      path.join(parsed.bootstrapArtifactsDir, `${suite}.summary.json`),
      path.join(parsed.bootstrapArtifactsDir, `${suite}.log`)
    )
    const sourceRun = hydrateRunItem(
      path.join(parsed.sourceArtifactsDir, `${suite}.run.json`),
      path.join(parsed.sourceArtifactsDir, `${suite}.summary.json`),
      path.join(parsed.sourceArtifactsDir, `${suite}.log`)
    )
    summary.current_phase = `classify:${suite}`
    const classification = classifySuite(suite, bootstrapRun, sourceRun, sourceBuild)
    summary.suite_classifications.push(classification)
    if (BLOCKER_SUITES.has(suite)) {
      summary.blocker_classifications.push(classification)
    }
    writeJson(summaryPath, summary)
  }

  finalizeSummary(summary, startedAt)
  writeJson(summaryPath, summary)
  console.log(`[full1-reconcile] summary=${summaryPath}`)
  console.log(summary.marker)
}

function runFullMode(parsed) {
  const startedAt = new Date()
  ensureDir(parsed.artifactsDir)
  ensureDir(parsed.bootstrapArtifactsDir)
  ensureDir(parsed.sourceArtifactsDir)
  const summaryPath = path.join(parsed.artifactsDir, 'bootstrap-source-reconciliation.summary.json')
  const summary = createSummary(parsed, startedAt, getCommitSha(parsed.root))
  writeJson(summaryPath, summary)

  summary.current_phase = 'bootstrap_build'
  writeJson(summaryPath, summary)
  const bootstrapBuild = buildHxhx(parsed.root, laneEnv('bootstrap'), laneProvidedBinary(parsed, 'bootstrap'), parsed.buildTimeoutSecs * 1000)
  if (bootstrapBuild.exit_code === 0 && bootstrapBuild.hxhx_bin) {
    bootstrapBuild.artifact_hxhx_bin = stageBinary(path.join(parsed.bootstrapArtifactsDir, 'hxhx'), bootstrapBuild.hxhx_bin)
  }
  summary.lanes.bootstrap.build = bootstrapBuild
  writeJson(path.join(parsed.bootstrapArtifactsDir, 'build.summary.json'), bootstrapBuild)
  writeJson(summaryPath, summary)

  summary.current_phase = 'source_build'
  writeJson(summaryPath, summary)
  const sourceBuild = buildHxhx(parsed.root, laneEnv('source'), laneProvidedBinary(parsed, 'source'), parsed.buildTimeoutSecs * 1000)
  if (sourceBuild.exit_code === 0 && sourceBuild.hxhx_bin) {
    sourceBuild.artifact_hxhx_bin = stageBinary(path.join(parsed.sourceArtifactsDir, 'hxhx'), sourceBuild.hxhx_bin)
  }
  summary.lanes.source.build = sourceBuild
  writeJson(path.join(parsed.sourceArtifactsDir, 'build.summary.json'), sourceBuild)
  writeJson(summaryPath, summary)

  const bootstrapSuiteRuns = {}
  if (bootstrapBuild.exit_code === 0 && bootstrapBuild.artifact_hxhx_bin) {
    for (const suite of parsed.suites) {
      summary.current_phase = `bootstrap_suite:${suite}`
      writeJson(summaryPath, summary)
      bootstrapSuiteRuns[suite] = runSuite(parsed.root, suite, bootstrapBuild.artifact_hxhx_bin, parsed.bootstrapArtifactsDir, laneEnv('bootstrap'), parsed.suiteTimeoutSecs * 1000)
      writeJson(path.join(parsed.bootstrapArtifactsDir, `${suite}.run.json`), bootstrapSuiteRuns[suite])
    }
  }

  const sourceSuiteRuns = {}
  if (sourceBuild.exit_code === 0 && sourceBuild.artifact_hxhx_bin) {
    for (const suite of parsed.suites) {
      summary.current_phase = `source_suite:${suite}`
      writeJson(summaryPath, summary)
      sourceSuiteRuns[suite] = runSuite(parsed.root, suite, sourceBuild.artifact_hxhx_bin, parsed.sourceArtifactsDir, laneEnv('source'), parsed.suiteTimeoutSecs * 1000)
      writeJson(path.join(parsed.sourceArtifactsDir, `${suite}.run.json`), sourceSuiteRuns[suite])
    }
  }

  for (const suite of parsed.suites) {
    summary.current_phase = `classify:${suite}`
    const classification = classifySuite(suite, bootstrapSuiteRuns[suite], sourceSuiteRuns[suite], sourceBuild)
    summary.suite_classifications.push(classification)
    if (BLOCKER_SUITES.has(suite)) {
      summary.blocker_classifications.push(classification)
    }
    writeJson(summaryPath, summary)
  }

  finalizeSummary(summary, startedAt)
  writeJson(summaryPath, summary)
  console.log(`[full1-reconcile] summary=${summaryPath}`)
  console.log(summary.marker)
}

function main() {
  let parsed
  try {
    parsed = parseArgs(process.argv.slice(2))
  } catch (error) {
    console.error(`[full1-reconcile] ERROR: ${String(error && error.message ? error.message : error)}`)
    process.exit(2)
  }

  switch (parsed.mode) {
    case 'build':
      runBuildMode(parsed)
      return
    case 'suite':
      runSuiteMode(parsed)
      return
    case 'classify':
      runClassifyMode(parsed)
      return
    case 'full':
    default:
      runFullMode(parsed)
  }
}

main()
