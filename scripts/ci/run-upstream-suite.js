#!/usr/bin/env node
/**
 * run-upstream-suite.js
 *
 * Full1 upstream suite runner with deterministic artifacts.
 * Runs one suite at a time in strict mode by default and emits suite markers on success.
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const SUITES = {
  misc: {
    marker: 'FULL1_SUITE_MISC:PASS',
    cwd: 'vendor/haxe/tests/misc',
    defaultArgs: ['compile.hxml'],
  },
  server: {
    marker: 'FULL1_SUITE_SERVER:PASS',
    cwd: 'vendor/haxe/tests/server',
    defaultArgs: ['run.hxml'],
  },
  threads: {
    marker: 'FULL1_SUITE_THREADS:PASS',
    cwd: 'vendor/haxe/tests/threads',
    defaultArgs: ['build.hxml'],
  },
  optimization: {
    marker: 'FULL1_SUITE_OPTIMIZATION:PASS',
    cwd: 'vendor/haxe/tests/optimization',
    defaultArgs: ['run.hxml'],
  },
  display: {
    marker: 'FULL1_SUITE_DISPLAY:PASS',
    cwd: 'vendor/haxe/tests/display',
    defaultArgs: ['build.hxml'],
  },
}

function fail(message) {
  console.error(`[full1-suite] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const out = {
    suite: '',
    strict: true,
    root: process.cwd(),
    upstreamDir: '',
    artifactsDir: '.artifacts/full1/suites',
    hxhxBin: process.env.HXHX_BIN || '',
    miscFilter: process.env.MISC_TEST_FILTER || '',
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--suite') {
      out.suite = String(argv[i + 1] || '').trim().toLowerCase()
      i += 1
      continue
    }
    if (arg === '--strict') {
      out.strict = true
      continue
    }
    if (arg === '--no-strict') {
      out.strict = false
      continue
    }
    if (arg === '--root') {
      out.root = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--upstream-dir') {
      out.upstreamDir = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--artifacts-dir') {
      out.artifactsDir = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--hxhx-bin') {
      out.hxhxBin = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--misc-filter') {
      out.miscFilter = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    fail(`unknown argument: ${arg}`)
  }

  if (!out.suite) {
    fail('missing required argument --suite <misc|server|threads|optimization|display>')
  }
  if (!(out.suite in SUITES)) {
    fail(`unsupported suite "${out.suite}"`)
  }
  if (!out.upstreamDir) {
    out.upstreamDir = path.join(out.root, 'vendor/haxe')
  }
  if (!fs.existsSync(out.upstreamDir)) {
    fail(`upstream checkout not found: ${out.upstreamDir}`)
  }
  if (!fs.existsSync(path.join(out.upstreamDir, 'tests'))) {
    fail(`upstream tests directory missing under: ${out.upstreamDir}`)
  }

  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function runCommand(command, args, options) {
  return cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64,
  })
}

function resolveHxhxBinary(root, currentValue) {
  if (currentValue) {
    const resolved = path.resolve(root, currentValue)
    if (fs.existsSync(resolved)) {
      return resolved
    }
    fail(`provided --hxhx-bin does not exist: ${resolved}`)
  }

  const buildScript = path.join(root, 'scripts/hxhx/build-hxhx.sh')
  const buildResult = runCommand('bash', [buildScript], {
    cwd: root,
    env: process.env,
  })
  const stdoutText = buildResult.stdout || ''
  const stderrText = buildResult.stderr || ''
  const buildText = `${stdoutText}${stderrText}`
  if (buildResult.status !== 0) {
    fail(`failed to build hxhx binary (exit ${buildResult.status})\n${buildText}`)
  }

  // build-hxhx.sh prints the binary path on stdout; stderr may include progress heartbeats.
  // Parse only stdout candidates so heartbeat/status lines can never be misread as a path.
  const stdoutLines = stdoutText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)

  const candidate = stdoutLines.length > 0 ? stdoutLines[stdoutLines.length - 1] : ''
  if (!candidate || candidate.startsWith('== ')) {
    fail('build-hxhx.sh did not print output binary path')
  }

  const resolved = path.resolve(root, candidate)
  if (!fs.existsSync(resolved)) {
    fail(`built hxhx binary path does not exist: ${resolved}`)
  }
  return resolved
}

function buildSuiteArgs(parsed, suiteConfig) {
  const args = []
  if (parsed.suite === 'misc' && parsed.miscFilter) {
    args.push('-D', `MISC_TEST_FILTER=${parsed.miscFilter}`)
  }
  args.push(...suiteConfig.defaultArgs)
  return args
}

function main() {
  const parsed = parseArgs(process.argv.slice(2))
  const suiteConfig = SUITES[parsed.suite]
  const suiteDir = path.join(parsed.root, suiteConfig.cwd)
  if (!fs.existsSync(suiteDir)) {
    fail(`suite directory not found: ${suiteDir}`)
  }

  ensureDir(parsed.artifactsDir)
  const logPath = path.join(parsed.artifactsDir, `${parsed.suite}.log`)
  const summaryPath = path.join(parsed.artifactsDir, `${parsed.suite}.summary.json`)

  const hxhxBin = resolveHxhxBinary(parsed.root, parsed.hxhxBin)
  const suiteArgs = buildSuiteArgs(parsed, suiteConfig)
  const env = { ...process.env }
  if (parsed.strict) {
    env.HXHX_FORBID_STAGE0 = '1'
  }

  const startedAt = new Date()
  const result = runCommand(hxhxBin, suiteArgs, {
    cwd: suiteDir,
    env,
  })
  const endedAt = new Date()
  const durationMs = endedAt.getTime() - startedAt.getTime()
  const stdout = result.stdout || ''
  const stderr = result.stderr || ''
  const combinedLog = [
    `suite=${parsed.suite}`,
    `strict=${parsed.strict ? '1' : '0'}`,
    `cwd=${suiteDir}`,
    `hxhx_bin=${hxhxBin}`,
    `command=${[hxhxBin, ...suiteArgs].join(' ')}`,
    `started_at=${startedAt.toISOString()}`,
    `ended_at=${endedAt.toISOString()}`,
    `duration_ms=${durationMs}`,
    '',
    '--- stdout ---',
    stdout,
    '--- stderr ---',
    stderr,
  ].join('\n')
  fs.writeFileSync(logPath, combinedLog, 'utf8')

  const summary = {
    schema: 'full1-upstream-suite-summary.v1',
    suite: parsed.suite,
    strict: parsed.strict,
    marker: suiteConfig.marker,
    command: [hxhxBin, ...suiteArgs],
    cwd: suiteDir,
    hxhx_bin: hxhxBin,
    artifacts: {
      log: logPath,
    },
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: durationMs,
    exit_code: result.status == null ? -1 : result.status,
    signal: result.signal || '',
  }
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8')

  if (result.error) {
    fail(`suite process spawn failed: ${String(result.error.message || result.error)}`)
  }
  if (result.status !== 0) {
    console.error(`[full1-suite] suite=${parsed.suite} failed (exit ${result.status}). log=${logPath}`)
    process.exit(result.status || 1)
  }

  console.log(`[full1-suite] suite=${parsed.suite} succeeded. log=${logPath}`)
  console.log(`[full1-suite] summary=${summaryPath}`)
  console.log(suiteConfig.marker)
}

main()
