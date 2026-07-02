#!/usr/bin/env node
/**
 * Run the local Full1 upstream suite set with the same artifact-sharing model
 * as CI: build shared binaries once, prepare haxelib dependencies once, then
 * execute independent suites concurrently.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const cp = require('child_process')
const { SUITES, SUITE_HAXELIB_DEPS } = require('./upstream-suite-config')

const INPROC_SUITES = new Set(['misc', 'threads', 'display'])
const EXTERNAL_HOST_SUITES = new Set(['server', 'optimization'])
const DEFAULT_SUITES = ['misc', 'server', 'threads', 'optimization', 'display']

function fail(message) {
  console.error(`[full1-suites] ERROR: ${message}`)
  process.exit(1)
}

function parseCsv(raw) {
  return String(raw || '')
    .split(',')
    .map((part) => part.trim().toLowerCase())
    .filter((part) => part.length > 0)
}

function parsePositiveInt(raw, name) {
  const value = String(raw || '').trim()
  if (!/^[0-9]+$/.test(value)) {
    fail(`${name} must be a positive integer, received "${raw}"`)
  }
  const parsed = Number(value)
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    fail(`${name} must be a positive integer, received "${raw}"`)
  }
  return parsed
}

function defaultJobCount(suiteCount) {
  const available = typeof os.availableParallelism === 'function'
    ? os.availableParallelism()
    : os.cpus().length
  return Math.max(1, Math.min(suiteCount, available || 1))
}

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    upstreamDir: '',
    artifactsDir: '.artifacts/full1/suites',
    hxhxBin: process.env.HXHX_BIN || '',
    macroHostBin: process.env.HXHX_MACRO_HOST_EXE || '',
    haxelibRepo: '',
    suites: DEFAULT_SUITES.slice(),
    jobs: 0,
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
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
    if (arg === '--macro-host-bin') {
      out.macroHostBin = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--haxelib-repo') {
      out.haxelibRepo = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--suites') {
      out.suites = parseCsv(argv[i + 1])
      i += 1
      continue
    }
    if (arg === '--jobs') {
      out.jobs = parsePositiveInt(argv[i + 1], '--jobs')
      i += 1
      continue
    }
    fail(`unknown argument: ${arg}`)
  }

  out.root = path.resolve(out.root)
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  out.haxelibRepo = out.haxelibRepo
    ? path.resolve(out.root, out.haxelibRepo)
    : path.join(out.artifactsDir, 'haxelib_repo')
  out.upstreamDir = out.upstreamDir ? path.resolve(out.root, out.upstreamDir) : ''
  if (out.suites.length === 0) {
    fail('missing suites')
  }
  for (const suite of out.suites) {
    if (!(suite in SUITES)) {
      fail(`unsupported suite "${suite}"`)
    }
    if (!INPROC_SUITES.has(suite) && !EXTERNAL_HOST_SUITES.has(suite)) {
      fail(`suite "${suite}" has no configured macro runtime mode`)
    }
  }
  if (out.jobs === 0) {
    const envJobs = String(process.env.FULL1_SUITE_JOBS || '').trim()
    out.jobs = envJobs ? parsePositiveInt(envJobs, 'FULL1_SUITE_JOBS') : defaultJobCount(out.suites.length)
  }
  out.jobs = Math.min(out.jobs, out.suites.length)
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function resolveConfiguredBinary(root, configured, name) {
  if (!configured) {
    return ''
  }
  const resolved = path.resolve(root, configured)
  if (!fs.existsSync(resolved)) {
    fail(`${name} does not exist: ${resolved}`)
  }
  return resolved
}

function makeLineWriter(prefix, stream) {
  let pending = ''
  return {
    write(data) {
      pending += data.toString()
      const lines = pending.split(/\r?\n/)
      pending = lines.pop()
      for (const line of lines) {
        stream.write(`${prefix}${line}\n`)
      }
    },
    flush() {
      if (pending.length > 0) {
        stream.write(`${prefix}${pending}\n`)
        pending = ''
      }
    },
  }
}

function runCapture(command, args, options) {
  return new Promise((resolve) => {
    const child = cp.spawn(command, args, {
      cwd: options.cwd,
      env: options.env || process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let stdout = ''
    let stderr = ''
    const stdoutWriter = options.stdoutPrefix ? makeLineWriter(options.stdoutPrefix, process.stdout) : null
    const stderrWriter = options.stderrPrefix ? makeLineWriter(options.stderrPrefix, process.stderr) : null

    child.stdout.on('data', (data) => {
      stdout += data.toString()
      if (stdoutWriter) {
        stdoutWriter.write(data)
      }
    })
    child.stderr.on('data', (data) => {
      stderr += data.toString()
      if (stderrWriter) {
        stderrWriter.write(data)
      }
    })
    child.on('error', (error) => {
      if (stdoutWriter) stdoutWriter.flush()
      if (stderrWriter) stderrWriter.flush()
      resolve({ status: -1, signal: '', stdout, stderr, error })
    })
    child.on('close', (status, signal) => {
      if (stdoutWriter) stdoutWriter.flush()
      if (stderrWriter) stderrWriter.flush()
      resolve({ status: status == null ? -1 : status, signal: signal || '', stdout, stderr, error: null })
    })
  })
}

function lastStdoutLine(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
  return lines.length > 0 ? lines[lines.length - 1] : ''
}

async function buildBinary(root, script, label) {
  console.log(`[full1-suites] building ${label}`)
  const result = await runCapture('bash', [script], {
    cwd: root,
    env: process.env,
    stderrPrefix: `[full1-suites:${label}:stderr] `,
  })
  if (result.status !== 0 || result.error) {
    fail(`failed to build ${label} (exit ${result.status})\n${result.stderr}${result.error ? result.error.message : ''}`)
  }
  const candidate = lastStdoutLine(result.stdout)
  if (!candidate || candidate.startsWith('== ')) {
    fail(`${script} did not print an output binary path`)
  }
  const resolved = path.resolve(root, candidate)
  if (!fs.existsSync(resolved)) {
    fail(`built ${label} path does not exist: ${resolved}`)
  }
  return resolved
}

function suitesWithHaxelibDeps(suites) {
  return suites.filter((suite) => (SUITE_HAXELIB_DEPS[suite] || []).length > 0)
}

async function prepareHaxelibRepo(parsed, depSuites) {
  if (depSuites.length === 0) {
    return ''
  }
  console.log(`[full1-suites] preparing haxelib repo for ${depSuites.join(',')}`)
  const summaryPath = path.join(parsed.artifactsDir, 'haxelib_repo.summary.json')
  const result = await runCapture(process.execPath, [
    'scripts/ci/prepare-suite-haxelib-deps.js',
    '--root', parsed.root,
    '--repo-path', parsed.haxelibRepo,
    '--summary-path', summaryPath,
    '--suites', depSuites.join(','),
  ], {
    cwd: parsed.root,
    env: process.env,
    stdoutPrefix: '[full1-suites:haxelib] ',
    stderrPrefix: '[full1-suites:haxelib:stderr] ',
  })
  if (result.status !== 0 || result.error) {
    fail(`failed to prepare haxelib repo (exit ${result.status})\n${result.stderr}${result.error ? result.error.message : ''}`)
  }
  return parsed.haxelibRepo
}

function suiteRuntimeMode(suite) {
  return EXTERNAL_HOST_SUITES.has(suite) ? 'external-host' : 'inproc'
}

function suiteArgs(parsed, suite, hxhxBin) {
  const args = [
    'scripts/ci/run-upstream-suite.js',
    '--suite', suite,
    '--strict',
    '--hxhx-bin', hxhxBin,
    '--artifacts-dir', parsed.artifactsDir,
  ]
  if (parsed.upstreamDir) {
    args.push('--upstream-dir', parsed.upstreamDir)
  }
  return args
}

async function runSuite(parsed, suite, shared) {
  const mode = suiteRuntimeMode(suite)
  const env = { ...process.env }
  if (shared.haxelibRepo) {
    env.HAXELIB_PATH = shared.haxelibRepo
  }
  env.HXHX_MACRO_RUNTIME_MODE = mode
  if (mode === 'external-host') {
    env.HXHX_MACRO_HOST_EXE = shared.macroHostBin
  } else {
    delete env.HXHX_MACRO_HOST_EXE
  }

  const startedAt = new Date()
  console.log(`[full1-suites] suite=${suite} mode=${mode} started`)
  const result = await runCapture(process.execPath, suiteArgs(parsed, suite, shared.hxhxBin), {
    cwd: parsed.root,
    env,
    stdoutPrefix: `[full1-suite:${suite}] `,
    stderrPrefix: `[full1-suite:${suite}:stderr] `,
  })
  const endedAt = new Date()
  const exitCode = result.error ? 1 : result.status
  const status = exitCode === 0 ? 'pass' : 'fail'
  console.log(`[full1-suites] suite=${suite} status=${status} elapsed_ms=${endedAt.getTime() - startedAt.getTime()}`)
  return {
    suite,
    mode,
    status,
    exit_code: exitCode,
    signal: result.signal,
    error: result.error ? String(result.error.message || result.error) : '',
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: endedAt.getTime() - startedAt.getTime(),
    summary: path.join(parsed.artifactsDir, `${suite}.summary.json`),
    log: path.join(parsed.artifactsDir, `${suite}.log`),
  }
}

async function runPool(tasks, jobs, runner) {
  const results = new Array(tasks.length)
  let next = 0
  const workerCount = Math.min(jobs, tasks.length)
  const workers = []
  for (let i = 0; i < workerCount; i += 1) {
    workers.push((async () => {
      while (next < tasks.length) {
        const current = next
        next += 1
        results[current] = await runner(tasks[current])
      }
    })())
  }
  await Promise.all(workers)
  return results
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2))
  ensureDir(parsed.artifactsDir)

  const startedAt = new Date()
  console.log(`[full1-suites] suites=${parsed.suites.join(',')} jobs=${parsed.jobs}`)

  let hxhxBin = resolveConfiguredBinary(parsed.root, parsed.hxhxBin, 'hxhx binary')
  if (!hxhxBin) {
    hxhxBin = await buildBinary(parsed.root, 'scripts/hxhx/build-hxhx.sh', 'hxhx')
  }

  let macroHostBin = resolveConfiguredBinary(parsed.root, parsed.macroHostBin, 'macro host binary')
  if (!macroHostBin && parsed.suites.some((suite) => suiteRuntimeMode(suite) === 'external-host')) {
    macroHostBin = await buildBinary(parsed.root, 'scripts/hxhx/build-hxhx-macro-host.sh', 'macro-host')
  }

  const depSuites = suitesWithHaxelibDeps(parsed.suites)
  const haxelibRepo = await prepareHaxelibRepo(parsed, depSuites)
  const shared = { hxhxBin, macroHostBin, haxelibRepo }
  const suiteResults = await runPool(parsed.suites, parsed.jobs, (suite) => runSuite(parsed, suite, shared))
  const failed = suiteResults.filter((result) => result.exit_code !== 0)
  const endedAt = new Date()
  const exitCode = failed.length === 0 ? 0 : 1
  const summary = {
    schema: 'full1-suites-strict-summary.v1',
    suites: suiteResults,
    jobs: parsed.jobs,
    hxhx_bin: hxhxBin,
    macro_host_bin: macroHostBin,
    haxelib_repo: haxelibRepo,
    artifacts_dir: parsed.artifactsDir,
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: endedAt.getTime() - startedAt.getTime(),
    exit_code: exitCode,
  }
  const summaryPath = path.join(parsed.artifactsDir, 'full1-suites-strict.summary.json')
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8')
  console.log(`[full1-suites] summary=${summaryPath}`)
  if (failed.length > 0) {
    console.error(`[full1-suites] failed suites: ${failed.map((result) => result.suite).join(', ')}`)
    process.exit(1)
  }
  console.log('[full1-suites] all suites succeeded')
}

main().catch((error) => fail(error && error.stack ? error.stack : String(error)))
