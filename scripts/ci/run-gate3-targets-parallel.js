#!/usr/bin/env node
/**
 * Run Full1 Gate3 targets with bounded target-level parallelism.
 *
 * Each target receives its own upstream worktree so RunCi patches, generated
 * target output, and local haxelib state cannot collide. The shared hxhx binary
 * is built once and passed into each child runner through HXHX_BIN.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const cp = require('child_process')

const DEFAULT_TARGETS = 'Macro,Js,Neko,Hl,Python,Java,Cs,Cpp,Lua,Php'
const DEFAULT_MARKER = 'FULL1_GATE3_EXTENDED_TARGETS:PASS'

function fail(message) {
  console.error(`[gate3-parallel] ERROR: ${message}`)
  process.exit(1)
}

function parseTargets(raw) {
  return String(raw || '')
    .split(/[,\s]+/)
    .map((target) => target.trim())
    .filter((target) => target.length > 0)
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

function defaultJobCount(targetCount) {
  const available = typeof os.availableParallelism === 'function'
    ? os.availableParallelism()
    : os.cpus().length
  return Math.max(1, Math.min(targetCount, available || 1, 3))
}

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    upstreamDir: process.env.HAXE_UPSTREAM_DIR || 'vendor/haxe',
    upstreamRef: process.env.HAXE_UPSTREAM_REF || '4.3.7',
    artifactsDir: process.env.FULL1_GATE3_EXTENDED_ARTIFACTS_DIR || '.artifacts/full1',
    targets: parseTargets(process.env.HXHX_GATE3_TARGETS || DEFAULT_TARGETS),
    jobs: 0,
    hxhxBin: process.env.HXHX_BIN || '',
    runner: 'scripts/hxhx/run-upstream-runci-targets.sh',
    marker: DEFAULT_MARKER,
    requireNoSkip: true,
    requireAllTargets: true,
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
    if (arg === '--upstream-ref') {
      out.upstreamRef = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--artifacts-dir') {
      out.artifactsDir = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--targets') {
      out.targets = parseTargets(argv[i + 1])
      i += 1
      continue
    }
    if (arg === '--jobs') {
      out.jobs = parsePositiveInt(argv[i + 1], '--jobs')
      i += 1
      continue
    }
    if (arg === '--hxhx-bin') {
      out.hxhxBin = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--runner') {
      out.runner = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--marker') {
      out.marker = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--allow-skip') {
      out.requireNoSkip = false
      continue
    }
    if (arg === '--allow-missing') {
      out.requireAllTargets = false
      continue
    }
    fail(`unknown argument: ${arg}`)
  }

  out.root = path.resolve(out.root)
  out.upstreamDir = path.resolve(out.root, out.upstreamDir)
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  out.runner = path.resolve(out.root, out.runner)
  if (out.targets.length === 0) {
    fail('missing targets')
  }
  if (!out.upstreamRef) {
    fail('missing upstream ref')
  }
  if (out.jobs === 0) {
    const envJobs = String(process.env.FULL1_GATE3_EXTENDED_TARGET_JOBS || process.env.HXHX_GATE3_TARGET_JOBS || '').trim()
    out.jobs = envJobs ? parsePositiveInt(envJobs, 'FULL1_GATE3_EXTENDED_TARGET_JOBS') : defaultJobCount(out.targets.length)
  }
  out.jobs = Math.min(out.jobs, out.targets.length)
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function safeName(value) {
  return String(value || '').replace(/[^A-Za-z0-9_.-]/g, '_')
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

function makeLineWriter(prefix, stream, logStream) {
  let pending = ''
  return {
    write(data) {
      pending += data.toString()
      const lines = pending.split(/\r?\n/)
      pending = lines.pop()
      for (const line of lines) {
        const out = `${prefix}${line}\n`
        stream.write(out)
        if (logStream) {
          logStream.write(`${line}\n`)
        }
      }
    },
    flush() {
      if (pending.length > 0) {
        const out = `${prefix}${pending}\n`
        stream.write(out)
        if (logStream) {
          logStream.write(`${pending}\n`)
        }
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
    const stdoutWriter = options.stdoutPrefix ? makeLineWriter(options.stdoutPrefix, process.stdout, options.logStream) : null
    const stderrWriter = options.stderrPrefix ? makeLineWriter(options.stderrPrefix, process.stderr, options.logStream) : null

    child.stdout.on('data', (data) => {
      stdout += data.toString()
      if (stdoutWriter) {
        stdoutWriter.write(data)
      } else if (options.logStream) {
        options.logStream.write(data)
      }
    })
    child.stderr.on('data', (data) => {
      stderr += data.toString()
      if (stderrWriter) {
        stderrWriter.write(data)
      } else if (options.logStream) {
        options.logStream.write(data)
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

function runSync(command, args, options) {
  const result = cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env || process.env,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64,
  })
  return {
    status: result.status == null ? -1 : result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    error: result.error || null,
  }
}

function requireCommandOk(command, args, options, label) {
  const result = runSync(command, args, options)
  if (result.status !== 0 || result.error) {
    fail(`${label} failed (exit ${result.status})\n${result.stdout}${result.stderr}${result.error ? result.error.message : ''}`)
  }
  return result.stdout
}

function lastStdoutLine(stdout) {
  const lines = String(stdout || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
  return lines.length > 0 ? lines[lines.length - 1] : ''
}

async function buildHxhx(parsed) {
  const configured = resolveConfiguredBinary(parsed.root, parsed.hxhxBin, 'hxhx binary')
  if (configured) {
    return configured
  }

  console.log('[gate3-parallel] building shared hxhx')
  const result = await runCapture('bash', ['scripts/hxhx/build-hxhx.sh'], {
    cwd: parsed.root,
    env: process.env,
    stderrPrefix: '[gate3-parallel:hxhx:stderr] ',
  })
  if (result.status !== 0 || result.error) {
    fail(`failed to build hxhx (exit ${result.status})\n${result.stderr}${result.error ? result.error.message : ''}`)
  }
  const candidate = lastStdoutLine(result.stdout)
  if (!candidate || candidate.startsWith('== ')) {
    fail('build-hxhx.sh did not print an output binary path')
  }
  const resolved = path.resolve(parsed.root, candidate)
  if (!fs.existsSync(resolved)) {
    fail(`built hxhx path does not exist: ${resolved}`)
  }
  return resolved
}

function validateUpstream(parsed) {
  if (!fs.existsSync(parsed.upstreamDir)) {
    fail(`upstream checkout not found: ${parsed.upstreamDir}`)
  }
  requireCommandOk('git', ['-C', parsed.upstreamDir, 'rev-parse', '--is-inside-work-tree'], {
    cwd: parsed.root,
    env: process.env,
  }, 'validate upstream checkout')
  const commit = requireCommandOk('git', ['-C', parsed.upstreamDir, 'rev-parse', `${parsed.upstreamRef}^{commit}`], {
    cwd: parsed.root,
    env: process.env,
  }, `resolve upstream ref ${parsed.upstreamRef}`).trim()
  return commit
}

function createTargetWorktrees(parsed, worktreeBase) {
  const worktrees = new Map()
  for (const target of parsed.targets) {
    const targetDir = path.join(worktreeBase, safeName(target))
    console.log(`[gate3-parallel] preparing upstream worktree target=${target}`)
    requireCommandOk('git', ['-C', parsed.upstreamDir, 'worktree', 'add', '--detach', targetDir, parsed.upstreamRef], {
      cwd: parsed.root,
      env: process.env,
    }, `create upstream worktree for ${target}`)
    worktrees.set(target, targetDir)
  }
  return worktrees
}

function removeTargetWorktrees(parsed, worktrees, worktreeBase, keep) {
  if (keep) {
    console.error(`[gate3-parallel] keeping target worktrees under ${worktreeBase}`)
    return
  }
  for (const [target, targetDir] of worktrees) {
    const result = runSync('git', ['-C', parsed.upstreamDir, 'worktree', 'remove', '--force', targetDir], {
      cwd: parsed.root,
      env: process.env,
    })
    if (result.status !== 0) {
      console.error(`[gate3-parallel] warning: failed to remove worktree target=${target}: ${result.stderr || result.stdout}`)
    }
  }
  fs.rmSync(worktreeBase, { recursive: true, force: true })
}

function parseSummaryFile(summaryPath) {
  if (!fs.existsSync(summaryPath)) {
    return null
  }
  return JSON.parse(fs.readFileSync(summaryPath, 'utf8'))
}

function summarizeTarget(parsed, target, logPath, summaryPath) {
  const args = [
    'scripts/ci/gate3-target-summary.js',
    '--log', logPath,
    '--targets', target,
    '--json-out', summaryPath,
    '--require-all-targets',
  ]
  if (parsed.requireNoSkip) {
    args.push('--require-no-skip')
  }
  const result = runSync(process.execPath, args, {
    cwd: parsed.root,
    env: process.env,
  })
  if (result.stdout) process.stdout.write(result.stdout)
  if (result.stderr) process.stderr.write(result.stderr)
  return result.status === 0 && !result.error
}

async function runTarget(parsed, target, shared) {
  const targetSafe = safeName(target)
  const logPath = path.join(shared.targetLogDir, `${targetSafe}.log`)
  const summaryPath = path.join(shared.targetSummaryDir, `${targetSafe}.summary.json`)
  ensureDir(path.dirname(logPath))
  ensureDir(path.dirname(summaryPath))
  const logStream = fs.createWriteStream(logPath, { flags: 'w' })
  const startedAt = new Date()
  console.log(`[gate3-parallel] target=${target} started`)

  const env = {
    ...process.env,
    HXHX_BIN: shared.hxhxBin,
    HXHX_GATE3_TARGETS: target,
    HAXE_UPSTREAM_DIR: shared.worktrees.get(target),
    HAXE_UPSTREAM_REF: parsed.upstreamRef,
    HXHX_GATE3_USE_PROVIDED_UPSTREAM_WORKTREE: '1',
    FULL1_GATE3_EXTENDED_ARTIFACTS_DIR: parsed.artifactsDir,
    HXHX_GATE3_FAILURE_ARTIFACTS_DIR: parsed.artifactsDir,
  }
  const result = await runCapture('bash', [parsed.runner, target], {
    cwd: parsed.root,
    env,
    stdoutPrefix: `[gate3:${target}] `,
    stderrPrefix: `[gate3:${target}:stderr] `,
    logStream,
  })
  await new Promise((resolve) => logStream.end(resolve))
  const summaryOk = summarizeTarget(parsed, target, logPath, summaryPath)
  const endedAt = new Date()
  const exitCode = result.error ? 1 : result.status
  const targetSummary = parseSummaryFile(summaryPath)
  const status = exitCode === 0 && summaryOk ? 'pass' : 'fail'
  console.log(`[gate3-parallel] target=${target} status=${status} elapsed_ms=${endedAt.getTime() - startedAt.getTime()}`)
  return {
    target,
    status,
    exit_code: exitCode,
    summary_ok: summaryOk,
    signal: result.signal,
    error: result.error ? String(result.error.message || result.error) : '',
    log: logPath,
    summary: summaryPath,
    parsed_summary: targetSummary,
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: endedAt.getTime() - startedAt.getTime(),
  }
}

async function runPool(tasks, jobs, runner) {
  const results = new Array(tasks.length)
  let next = 0
  const workers = []
  for (let i = 0; i < Math.min(jobs, tasks.length); i += 1) {
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

function writeAggregateLog(results, aggregateLogPath) {
  const chunks = []
  for (const result of results) {
    chunks.push(`\n===== target ${result.target} log=${result.log} =====\n`)
    if (fs.existsSync(result.log)) {
      chunks.push(fs.readFileSync(result.log, 'utf8'))
    } else {
      chunks.push(`missing log for target ${result.target}\n`)
    }
  }
  fs.writeFileSync(aggregateLogPath, chunks.join(''), 'utf8')
}

function buildAggregateSummary(parsed, results, startedAt, endedAt, hxhxBin) {
  const entries = []
  const targetsRan = []
  const targetsSkipped = []
  const targetsFailed = []
  const targetsMissing = []

  for (const result of results) {
    const summary = result.parsed_summary
    if (!summary || !Array.isArray(summary.entries) || summary.entries.length === 0) {
      targetsMissing.push(result.target)
      continue
    }
    for (const entry of summary.entries) {
      entries.push(entry)
      targetsRan.push(entry.target)
      if (entry.status === 'SKIP') targetsSkipped.push(entry.target)
      if (entry.status === 'FAIL') targetsFailed.push(entry.target)
    }
    if (result.exit_code !== 0 || !result.summary_ok) {
      if (!targetsFailed.includes(result.target)) {
        targetsFailed.push(result.target)
      }
    }
  }

  const ranSet = new Set(targetsRan)
  for (const target of parsed.targets) {
    if (!ranSet.has(target) && !targetsMissing.includes(target)) {
      targetsMissing.push(target)
    }
  }

  return {
    schema: 'gate3-extended-summary.v1',
    targets_requested: parsed.targets,
    targets_ran: targetsRan,
    targets_skipped: targetsSkipped,
    targets_failed: targetsFailed,
    targets_missing: targetsMissing,
    entries,
    strict_no_skip: parsed.requireNoSkip,
    target_jobs: parsed.jobs,
    hxhx_bin: hxhxBin,
    target_results: results.map((result) => ({
      target: result.target,
      status: result.status,
      exit_code: result.exit_code,
      summary_ok: result.summary_ok,
      signal: result.signal,
      error: result.error,
      log: result.log,
      summary: result.summary,
      started_at: result.started_at,
      ended_at: result.ended_at,
      duration_ms: result.duration_ms,
    })),
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: endedAt.getTime() - startedAt.getTime(),
  }
}

async function main() {
  const parsed = parseArgs(process.argv.slice(2))
  ensureDir(parsed.artifactsDir)
  const targetLogDir = path.join(parsed.artifactsDir, 'gate3-target-logs')
  const targetSummaryDir = path.join(parsed.artifactsDir, 'gate3-target-summaries')
  ensureDir(targetLogDir)
  ensureDir(targetSummaryDir)
  if (!fs.existsSync(parsed.runner)) {
    fail(`target runner not found: ${parsed.runner}`)
  }
  const startedAt = new Date()
  const upstreamCommit = validateUpstream(parsed)
  const hxhxBin = await buildHxhx(parsed)
  const worktreeBase = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-gate3-targets-'))
  const worktrees = createTargetWorktrees(parsed, worktreeBase)
  const shared = { hxhxBin, worktrees, targetLogDir, targetSummaryDir }
  let results = []
  let keepWorktrees = false
  try {
    console.log(`[gate3-parallel] targets=${parsed.targets.join(',')} jobs=${parsed.jobs} upstream_ref=${parsed.upstreamRef} upstream_commit=${upstreamCommit}`)
    results = await runPool(parsed.targets, parsed.jobs, (target) => runTarget(parsed, target, shared))
    keepWorktrees = results.some((result) => result.exit_code !== 0) && process.env.HXHX_GATE3_KEEP_WORKTREE_ON_FAILURE === '1'
  } finally {
    removeTargetWorktrees(parsed, worktrees, worktreeBase, keepWorktrees)
  }

  const endedAt = new Date()
  const aggregateLogPath = path.join(parsed.artifactsDir, 'gate3-full1-extended.log')
  const aggregateSummaryPath = path.join(parsed.artifactsDir, 'gate3-full1-extended.summary.json')
  writeAggregateLog(results, aggregateLogPath)
  const aggregate = buildAggregateSummary(parsed, results, startedAt, endedAt, hxhxBin)
  fs.writeFileSync(aggregateSummaryPath, `${JSON.stringify(aggregate, null, 2)}\n`, 'utf8')
  console.log(`[gate3-parallel] log=${aggregateLogPath}`)
  console.log(`[gate3-parallel] summary=${aggregateSummaryPath}`)

  if (parsed.requireAllTargets && aggregate.targets_missing.length > 0) {
    console.error(`[gate3-parallel] missing target summaries: ${aggregate.targets_missing.join(', ')}`)
  }
  if (parsed.requireNoSkip && aggregate.targets_skipped.length > 0) {
    console.error(`[gate3-parallel] strict mode violation: skipped targets: ${aggregate.targets_skipped.join(', ')}`)
  }
  if (aggregate.targets_failed.length > 0) {
    console.error(`[gate3-parallel] failing targets: ${aggregate.targets_failed.join(', ')}`)
  }
  if (
    (parsed.requireAllTargets && aggregate.targets_missing.length > 0)
    || (parsed.requireNoSkip && aggregate.targets_skipped.length > 0)
    || aggregate.targets_failed.length > 0
  ) {
    process.exit(1)
  }
  if (parsed.marker) {
    console.log(parsed.marker)
  }
}

main().catch((error) => fail(error && error.stack ? error.stack : String(error)))
