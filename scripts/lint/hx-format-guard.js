#!/usr/bin/env node
'use strict'

const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn, spawnSync } = require('child_process')

const DEFAULT_FORMATTER_TIMEOUT_MS = 4 * 60 * 1000
const DEFAULT_OVERSIZED_JOBS = 2

/**
 * Checks all tracked Haxe files with the official haxelib formatter.
 *
 * Haxe Formatter 1.18.0 does not expose an internal jobs flag, and one repo-wide
 * formatter invocation is one of the slower local guards. This helper keeps the
 * formatter as the source of truth, but isolates oversized files from ordinary
 * line-balanced chunks and runs those deterministic tasks through a bounded work
 * queue. Oversized files use at most two lanes, instead of occupying every
 * worker, while ordinary chunks continue in parallel. Set HX_FORMAT_JOBS=1 for
 * serial debugging or a positive integer to override the default auto cap.
 * HX_FORMAT_OVERSIZED_JOBS can lower the heavy-task cap for a constrained host,
 * and HX_FORMAT_TIMEOUT_SECONDS bounds one formatter task.
 */

function fail(message) {
  console.error(`[guard:hx-format] ERROR: ${message}`)
  process.exit(1)
}

function commandOutput(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || process.cwd(),
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe']
  })
  if (result.error) fail(`${command} is required: ${result.error.message}`)
  if (result.status !== 0) {
    const output = `${result.stdout || ''}${result.stderr || ''}`.trim()
    fail(`${command} ${args.join(' ')} failed${output ? `:\n${output}` : ''}`)
  }
  return result.stdout
}

function repoRoot() {
  return commandOutput('git', ['rev-parse', '--show-toplevel']).trim()
}

function formatterHelp(root) {
  const result = spawnSync('haxelib', ['run', 'formatter', '--help'], {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe']
  })
  if (result.error) fail(`haxelib is required: ${result.error.message}`)
  if (result.status !== 0) {
    console.error('[guard:hx-format] ERROR: formatter haxelib is not installed.')
    console.error('[guard:hx-format] Install it with: haxelib install formatter')
    process.exit(1)
  }
}

function trackedHaxeFiles(root) {
  const tracked = commandOutput('git', ['ls-files', '*.hx'], { cwd: root })
    .split(/\r?\n/)
    .filter(Boolean)
    .filter(file => !/(^|\/)(deps|out|bootstrap_work|bootstrap_verify)\//.test(file))
  return existingFiles(root, tracked)
}

/**
 * Removes tracked paths that were deleted in the working tree.
 *
 * `git ls-files` keeps reporting a deleted file until its deletion is staged.
 * A rename should therefore skip the old path instead of crashing while trying
 * to count lines before the official formatter starts.
 */
function existingFiles(root, files, exists = fs.existsSync) {
  return files.filter(file => exists(path.join(root, file)))
}

function countLines(root, file) {
  const text = fs.readFileSync(path.join(root, file), 'utf8')
  if (text.length === 0) return 0
  let lines = 1
  for (let i = 0; i < text.length; i += 1) {
    if (text.charCodeAt(i) === 10 && i !== text.length - 1) lines += 1
  }
  return lines
}

function parseJobs(value, fileCount) {
  const cpuCount = typeof os.availableParallelism === 'function' ? os.availableParallelism() : os.cpus().length
  if (!value || value === 'auto') return Math.max(1, Math.min(4, cpuCount, fileCount))
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed < 1) fail(`HX_FORMAT_JOBS must be a positive integer or "auto", got ${value}`)
  return Math.min(parsed, fileCount)
}

function parseFormatterTimeoutMs(value) {
  if (!value) return DEFAULT_FORMATTER_TIMEOUT_MS
  const seconds = Number(value)
  if (!Number.isFinite(seconds) || seconds <= 0) fail(`HX_FORMAT_TIMEOUT_SECONDS must be a positive number, got ${value}`)
  return Math.ceil(seconds * 1000)
}

function parseOversizedJobs(value, jobs) {
  if (!value) return Math.min(DEFAULT_OVERSIZED_JOBS, jobs)
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed < 1) {
    fail(`HX_FORMAT_OVERSIZED_JOBS must be a positive integer, got ${value}`)
  }
  return Math.min(parsed, jobs)
}

function balancedBuckets(files, jobs) {
  const buckets = Array.from({ length: jobs }, () => ({ files: [], lines: 0 }))
  for (const file of files) {
    let target = buckets[0]
    for (const bucket of buckets) {
      if (bucket.lines < target.lines || (bucket.lines === target.lines && bucket.files.length < target.files.length)) {
        target = bucket
      }
    }
    target.files.push(file.path)
    target.lines += file.lines
  }
  return buckets.filter(bucket => bucket.files.length > 0)
}

/**
 * Builds deterministic formatter tasks without pretending that line count is a
 * precise cost model. Files large enough to dominate a worker become singleton
 * tasks; the rest stay line-balanced. The bounded runner can then reuse workers
 * as quick tasks finish instead of making one slow file own unrelated work.
 */
function buildFormatterBuckets(files, jobs) {
  const totalLines = files.reduce((sum, file) => sum + file.lines, 0)
  const oversizedThreshold = Math.max(1, Math.ceil(totalLines / (jobs * 4)))
  const oversized = []
  const ordinary = []

  for (const file of files) {
    if (jobs > 1 && file.lines >= oversizedThreshold) {
      oversized.push({ files: [file.path], lines: file.lines, oversized: true })
    } else {
      ordinary.push(file)
    }
  }

  const ordinaryBuckets =
    ordinary.length > 0 ? balancedBuckets(ordinary, Math.min(jobs, ordinary.length)).map(bucket => ({ ...bucket, oversized: false })) : []
  return {
    buckets: oversized.concat(ordinaryBuckets),
    oversizedThreshold,
    isolatedFileCount: oversized.length
  }
}

function killProcessTree(child) {
  try {
    if (process.platform !== 'win32' && child.pid) {
      process.kill(-child.pid, 'SIGKILL')
    } else {
      child.kill('SIGKILL')
    }
  } catch (error) {
    if (!error || error.code !== 'ESRCH') throw error
  }
}

/**
 * Runs one child process with captured output and a hard deadline.
 *
 * Formatter wrappers can create grandchildren. On POSIX we therefore give the
 * command its own process group and terminate the complete group on timeout,
 * preventing an abandoned formatter or Neko process from leaking into later
 * developer commands.
 */
function runCommandWithTimeout(command, args, options = {}) {
  return new Promise(resolve => {
    const started = Date.now()
    const timeoutMs = options.timeoutMs || DEFAULT_FORMATTER_TIMEOUT_MS
    const child = spawn(command, args, {
      cwd: options.cwd || process.cwd(),
      env: options.env || process.env,
      detached: process.platform !== 'win32',
      stdio: ['ignore', 'pipe', 'pipe']
    })
    let stdout = ''
    let stderr = ''
    let finished = false
    let timedOut = false
    let timer = null

    function finish(result) {
      if (finished) return
      finished = true
      if (timer) clearTimeout(timer)
      resolve({
        ...result,
        pid: child.pid,
        timedOut,
        timeoutMs,
        elapsedMs: Date.now() - started,
        stdout,
        stderr
      })
    }

    child.stdout.on('data', chunk => {
      stdout += chunk
    })
    child.stderr.on('data', chunk => {
      stderr += chunk
    })
    child.on('error', error => finish({ error }))
    child.on('close', (code, signal) => finish({ code, signal }))

    timer = setTimeout(() => {
      timedOut = true
      killProcessTree(child)
    }, timeoutMs)
  })
}

async function runFormatter(root, bucket, index, total) {
  const args = ['run', 'formatter']
  for (const file of bucket.files) args.push('-s', file)
  args.push('--check')
  const result = await runCommandWithTimeout('haxelib', args, {
    cwd: root,
    env: process.env,
    timeoutMs: parseFormatterTimeoutMs(process.env.HX_FORMAT_TIMEOUT_SECONDS)
  })
  return { index, total, bucket, ...result }
}

function printFormatterOutput(result) {
  const output = `${result.stdout || ''}${result.stderr || ''}`.trim()
  if (output) console.error(output)
}

/**
 * Executes the complete formatter plan and reports results in stable task order.
 * Failures include the exact owning file list, while worker summaries expose the
 * effective load balance without making completion order part of correctness.
 */
async function runFormatCheck(root, buckets, jobs, oversizedJobs) {
  const started = Date.now()
  const results = await runFormatterQueue(root, buckets, Math.min(buckets.length, jobs), runFormatter, oversizedJobs)
  let failed = false
  for (const result of results) {
    const seconds = (result.elapsedMs / 1000).toFixed(3)
    const status = result.timedOut
      ? `timeout=${(result.timeoutMs / 1000).toFixed(0)}s`
      : result.error
        ? 'error'
        : result.code === 0
          ? 'ok'
          : `exit=${result.code}${result.signal ? ` signal=${result.signal}` : ''}`
    console.log(
      `[guard:hx-format] chunk ${result.index}/${result.total} ${status} files=${result.bucket.files.length} lines=${result.bucket.lines} elapsed=${seconds}s`
    )
    if (result.error || result.code !== 0) {
      failed = true
      console.error(`[guard:hx-format] chunk ${result.index}/${result.total} files:\n${result.bucket.files.join('\n')}`)
      if (result.timedOut) {
        console.error(`[guard:hx-format] ERROR: formatter task exceeded its ${(result.timeoutMs / 1000).toFixed(0)}s deadline.`)
      }
      if (result.error) console.error(`[guard:hx-format] ERROR: ${result.error.message}`)
      printFormatterOutput(result)
    }
  }
  const workerTotals = new Map()
  for (const result of results) {
    const current = workerTotals.get(result.worker) || { elapsedMs: 0, tasks: 0, files: 0, lines: 0 }
    current.elapsedMs += result.elapsedMs
    current.tasks += 1
    current.files += result.bucket.files.length
    current.lines += result.bucket.lines
    workerTotals.set(result.worker, current)
  }
  for (const [worker, summary] of [...workerTotals.entries()].sort((left, right) => left[0] - right[0])) {
    console.log(
      `[guard:hx-format] worker ${worker}/${workerTotals.size} tasks=${summary.tasks} files=${summary.files} lines=${summary.lines} elapsed=${(summary.elapsedMs / 1000).toFixed(3)}s`
    )
  }
  if (failed) process.exit(1)
  return Date.now() - started
}

/**
 * Runs deterministic formatter tasks with at most `jobs` child processes.
 *
 * When oversized singleton files exist, a small bounded group processes them.
 * At least one worker remains available for ordinary chunks, and heavy workers
 * help ordinary work after their own queue finishes. This avoids both failure
 * modes: every worker cannot be consumed by mega-files, and normal files do not
 * wait behind the complete heavy queue.
 */
async function runFormatterQueue(root, buckets, jobs, runner = runFormatter, oversizedJobs = DEFAULT_OVERSIZED_JOBS) {
  const results = new Array(buckets.length)

  async function runIndex(index, worker) {
    const result = await runner(root, buckets[index], index + 1, buckets.length)
    results[index] = { ...result, worker }
  }

  if (jobs === 1) {
    for (let index = 0; index < buckets.length; index += 1) await runIndex(index, 1)
    return results
  }

  const oversizedIndexes = []
  const ordinaryIndexes = []
  for (let index = 0; index < buckets.length; index += 1) {
    ;(buckets[index].oversized ? oversizedIndexes : ordinaryIndexes).push(index)
  }

  let nextOrdinary = 0
  async function workOrdinary(worker) {
    while (nextOrdinary < ordinaryIndexes.length) {
      const ordinaryIndex = nextOrdinary
      nextOrdinary += 1
      await runIndex(ordinaryIndexes[ordinaryIndex], worker)
    }
  }

  if (oversizedIndexes.length === 0) {
    const workerCount = Math.min(jobs, ordinaryIndexes.length)
    await Promise.all(Array.from({ length: workerCount }, (_unused, index) => workOrdinary(index + 1)))
    return results
  }

  let nextOversized = 0
  async function workOversizedThenHelp(worker) {
    while (nextOversized < oversizedIndexes.length) {
      const oversizedIndex = nextOversized
      nextOversized += 1
      await runIndex(oversizedIndexes[oversizedIndex], worker)
    }
    await workOrdinary(worker)
  }

  const maximumOversizedWorkers = ordinaryIndexes.length > 0 ? jobs - 1 : jobs
  const oversizedWorkerCount = Math.min(oversizedJobs, maximumOversizedWorkers, oversizedIndexes.length)
  const active = []
  for (let index = 0; index < oversizedWorkerCount; index += 1) active.push(workOversizedThenHelp(index + 1))
  const ordinaryWorkerCount = Math.min(jobs - oversizedWorkerCount, ordinaryIndexes.length)
  for (let index = 0; index < ordinaryWorkerCount; index += 1) {
    active.push(workOrdinary(oversizedWorkerCount + index + 1))
  }
  await Promise.all(active)
  return results
}

function hashFile(file) {
  return crypto.createHash('sha1').update(fs.readFileSync(file)).digest('hex')
}

function runFormatterSync(root, args, label) {
  const result = spawnSync('haxelib', ['run', 'formatter', ...args], {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe']
  })
  if (result.error) fail(`${label} failed: ${result.error.message}`)
  if (result.status !== 0) {
    const output = `${result.stdout || ''}${result.stderr || ''}`.trim()
    fail(`${label} failed${output ? `:\n${output}` : ''}`)
  }
}

function checkSentinelDeterminism(root) {
  const sentinel = path.join(root, 'packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx')
  if (!fs.existsSync(sentinel)) return
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hx-format-sentinel-'))
  const tmpFile = path.join(tmpDir, path.basename(sentinel))
  try {
    fs.copyFileSync(sentinel, tmpFile)
    runFormatterSync(root, ['-s', tmpFile], 'sentinel formatter pass 1')
    const hashFirst = hashFile(tmpFile)
    runFormatterSync(root, ['-s', tmpFile], 'sentinel formatter pass 2')
    const hashSecond = hashFile(tmpFile)
    if (hashFirst !== hashSecond) fail(`formatter output is nondeterministic for ${path.relative(root, sentinel)}`)
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

async function main() {
  const root = repoRoot()
  process.chdir(root)
  formatterHelp(root)

  const filePaths = trackedHaxeFiles(root)
  if (filePaths.length === 0) fail('no tracked .hx files found.')
  const files = filePaths
    .map(file => ({ path: file, lines: countLines(root, file) }))
    .sort((a, b) => b.lines - a.lines || a.path.localeCompare(b.path))
  const totalLines = files.reduce((sum, file) => sum + file.lines, 0)
  const jobs = parseJobs(process.env.HX_FORMAT_JOBS || 'auto', files.length)
  const oversizedJobs = parseOversizedJobs(process.env.HX_FORMAT_OVERSIZED_JOBS, jobs)
  const timeoutMs = parseFormatterTimeoutMs(process.env.HX_FORMAT_TIMEOUT_SECONDS)
  const plan = buildFormatterBuckets(files, jobs)

  console.log(
    `[guard:hx-format] Checking Haxe formatting with jobs=${jobs} tasks=${plan.buckets.length} isolated=${plan.isolatedFileCount} oversized_jobs=${oversizedJobs} timeout=${(timeoutMs / 1000).toFixed(0)}s isolate_at_lines=${plan.oversizedThreshold} files=${files.length} lines=${totalLines}...`
  )
  const elapsedMs = await runFormatCheck(root, plan.buckets, jobs, oversizedJobs)
  checkSentinelDeterminism(root)
  console.log(`[guard:hx-format] OK: Haxe formatting is clean. elapsed=${(elapsedMs / 1000).toFixed(3)}s`)
}

if (require.main === module) {
  main().catch(error => fail(error && error.stack ? error.stack : String(error)))
}

module.exports = {
  balancedBuckets,
  buildFormatterBuckets,
  existingFiles,
  runCommandWithTimeout,
  runFormatterQueue
}
