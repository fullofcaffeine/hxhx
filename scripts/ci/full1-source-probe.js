#!/usr/bin/env node
/**
 * full1-source-probe.js
 *
 * Non-blocking diagnostic lane for Full1:
 * - Build hxhx from source (HXHX_FORCE_STAGE0=1)
 * - Reuse that binary for selected strict upstream suites
 * - Emit FULL1_SOURCE_BUILD_PROBE:PASS or FULL1_SOURCE_BUILD_PROBE:WARN
 *
 * This script is intentionally non-blocking (exit code 0) so it can run as
 * scheduled evidence without destabilizing the primary bootstrap-based matrix.
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const DEFAULT_SUITES = ['server', 'optimization']
const SUMMARY_TAIL_CHARS = 4000

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    artifactsDir: '.artifacts/full1/source-probe',
    suites: DEFAULT_SUITES.slice(),
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
    throw new Error(`unknown argument: ${arg}`)
  }

  if (out.suites.length === 0) {
    throw new Error('no suites selected for source probe')
  }

  out.root = path.resolve(out.root)
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
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
    killSignal: 'SIGTERM',
  })
}

function positiveInt(value, fallback) {
  const parsed = Number.parseInt(String(value || '').trim(), 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
}

function commandTimedOut(result) {
  return Boolean(result && result.error && result.error.code === 'ETIMEDOUT')
}

function normalizedExitCode(result) {
  if (commandTimedOut(result)) {
    return -1
  }
  return result.status == null ? -1 : result.status
}

function relativeArtifactPath(root, filePath) {
  return path.relative(root, filePath).split(path.sep).join('/')
}

function logSummary(root, filePath, text) {
  const content = String(text || '')
  fs.writeFileSync(filePath, content, 'utf8')
  return {
    log: relativeArtifactPath(root, filePath),
    bytes: Buffer.byteLength(content, 'utf8'),
    tail: content.length > SUMMARY_TAIL_CHARS
      ? content.slice(content.length - SUMMARY_TAIL_CHARS)
      : content,
  }
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

function main() {
  const startedAt = new Date()
  let parsed
  try {
    parsed = parseArgs(process.argv.slice(2))
  } catch (error) {
    console.error(`[full1-source-probe] ERROR: ${String(error && error.message ? error.message : error)}`)
    process.exit(2)
  }

  ensureDir(parsed.artifactsDir)
  const suitesArtifactsDir = path.join(parsed.artifactsDir, 'suites')
  ensureDir(suitesArtifactsDir)

  const summary = {
    schema: 'full1-source-probe-summary.v2',
    started_at: startedAt.toISOString(),
    root: parsed.root,
    suites: parsed.suites,
    build: {
      attempted: true,
      exit_code: null,
      hxhx_bin: '',
      stdout_log: '',
      stderr_log: '',
      stdout_bytes: 0,
      stderr_bytes: 0,
      stdout_tail: '',
      stderr_tail: '',
      timeout_sec: null,
      timed_out: false,
      usable_after_timeout: false,
      signal: '',
      error: '',
    },
    suites_run: [],
    marker: 'FULL1_SOURCE_BUILD_PROBE:WARN',
    status: 'warn',
  }

  const env = { ...process.env }
  env.HXHX_FORCE_STAGE0 = env.HXHX_FORCE_STAGE0 || '1'
  env.HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS = env.HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS || '900'
  env.HXHX_STAGE0_CONNECT_IDLE_SECS = env.HXHX_STAGE0_CONNECT_IDLE_SECS || '45'
  env.FULL1_SOURCE_PROBE_BUILD_TIMEOUT_SECS = env.FULL1_SOURCE_PROBE_BUILD_TIMEOUT_SECS || '960'
  env.FULL1_SOURCE_PROBE_SUITE_TIMEOUT_SECS = env.FULL1_SOURCE_PROBE_SUITE_TIMEOUT_SECS || '600'

  const buildTimeoutSec = positiveInt(env.FULL1_SOURCE_PROBE_BUILD_TIMEOUT_SECS, 960)
  const suiteTimeoutSec = positiveInt(env.FULL1_SOURCE_PROBE_SUITE_TIMEOUT_SECS, 600)

  const buildScript = path.join(parsed.root, 'scripts/hxhx/build-hxhx.sh')
  const buildResult = run('bash', [buildScript], {
    cwd: parsed.root,
    env,
    timeoutMs: buildTimeoutSec * 1000,
  })
  summary.build.exit_code = normalizedExitCode(buildResult)
  summary.build.timeout_sec = buildTimeoutSec
  summary.build.timed_out = commandTimedOut(buildResult)
  summary.build.signal = buildResult.signal || ''
  const buildStdout = logSummary(
    parsed.root,
    path.join(parsed.artifactsDir, 'build.stdout.log'),
    buildResult.stdout || ''
  )
  const buildStderr = logSummary(
    parsed.root,
    path.join(parsed.artifactsDir, 'build.stderr.log'),
    buildResult.stderr || ''
  )
  summary.build.stdout_log = buildStdout.log
  summary.build.stderr_log = buildStderr.log
  summary.build.stdout_bytes = buildStdout.bytes
  summary.build.stderr_bytes = buildStderr.bytes
  summary.build.stdout_tail = buildStdout.tail
  summary.build.stderr_tail = buildStderr.tail
  summary.build.error = buildResult.error ? String(buildResult.error.message || buildResult.error) : ''

  let hxhxBin = ''
  if (summary.build.exit_code === 0 || summary.build.timed_out) {
    const candidate = parseBuildBinaryPath(buildResult.stdout || '')
    if (candidate.length > 0) {
      const resolved = path.resolve(parsed.root, candidate)
      if (fs.existsSync(resolved)) {
        hxhxBin = resolved
        summary.build.hxhx_bin = resolved
        summary.build.usable_after_timeout = summary.build.timed_out
      }
    }
  }

  if (hxhxBin.length > 0) {
    for (const suite of parsed.suites) {
      const suiteStartedAt = new Date()
      const suiteResult = run(
        'node',
        [
          path.join(parsed.root, 'scripts/ci/run-upstream-suite.js'),
          '--suite',
          suite,
          '--strict',
          '--hxhx-bin',
          hxhxBin,
          '--artifacts-dir',
          suitesArtifactsDir,
        ],
        {
          cwd: parsed.root,
          env,
          timeoutMs: suiteTimeoutSec * 1000,
        }
      )
      const suiteEndedAt = new Date()
      const suiteStdout = logSummary(
        parsed.root,
        path.join(suitesArtifactsDir, `${suite}.source-probe.stdout.log`),
        suiteResult.stdout || ''
      )
      const suiteStderr = logSummary(
        parsed.root,
        path.join(suitesArtifactsDir, `${suite}.source-probe.stderr.log`),
        suiteResult.stderr || ''
      )
      summary.suites_run.push({
        suite,
        started_at: suiteStartedAt.toISOString(),
        ended_at: suiteEndedAt.toISOString(),
        duration_ms: suiteEndedAt.getTime() - suiteStartedAt.getTime(),
        exit_code: normalizedExitCode(suiteResult),
        timeout_sec: suiteTimeoutSec,
        timed_out: commandTimedOut(suiteResult),
        signal: suiteResult.signal || '',
        stdout_log: suiteStdout.log,
        stderr_log: suiteStderr.log,
        stdout_bytes: suiteStdout.bytes,
        stderr_bytes: suiteStderr.bytes,
        stdout_tail: suiteStdout.tail,
        stderr_tail: suiteStderr.tail,
        error: suiteResult.error ? String(suiteResult.error.message || suiteResult.error) : '',
      })
    }
  }

  const allSuitePass = summary.suites_run.length === parsed.suites.length
    && summary.suites_run.every((runItem) => runItem.exit_code === 0)
  const buildPass = summary.build.exit_code === 0 && hxhxBin.length > 0

  if (buildPass && allSuitePass) {
    summary.status = 'pass'
    summary.marker = 'FULL1_SOURCE_BUILD_PROBE:PASS'
  } else {
    summary.status = 'warn'
    summary.marker = 'FULL1_SOURCE_BUILD_PROBE:WARN'
  }

  const endedAt = new Date()
  summary.ended_at = endedAt.toISOString()
  summary.duration_ms = endedAt.getTime() - startedAt.getTime()

  const summaryPath = path.join(parsed.artifactsDir, 'source-probe.summary.json')
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8')

  console.log(`[full1-source-probe] summary=${summaryPath}`)
  console.log(summary.marker)
}

main()
