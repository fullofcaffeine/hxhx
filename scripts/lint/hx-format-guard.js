#!/usr/bin/env node
'use strict'

const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn, spawnSync } = require('child_process')

/**
 * Checks all tracked Haxe files with the official haxelib formatter.
 *
 * Haxe Formatter 1.18.0 does not expose an internal jobs flag, and one repo-wide
 * formatter invocation is one of the slower local guards. This helper keeps the
 * formatter as the source of truth, but shards the same tracked file list into
 * deterministic, line-balanced chunks and runs independent `haxelib run formatter
 * --check` processes in parallel. Set HX_FORMAT_JOBS=1 for serial debugging or a
 * positive integer to override the default auto cap.
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
  return commandOutput('git', ['ls-files', '*.hx'], { cwd: root })
    .split(/\r?\n/)
    .filter(Boolean)
    .filter(file => !/(^|\/)(deps|out|bootstrap_work|bootstrap_verify)\//.test(file))
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

function runFormatter(root, bucket, index, total) {
  return new Promise(resolve => {
    const args = ['run', 'formatter']
    for (const file of bucket.files) args.push('-s', file)
    args.push('--check')
    const started = Date.now()
    const child = spawn('haxelib', args, { cwd: root, env: process.env })
    let stdout = ''
    let stderr = ''

    child.stdout.on('data', chunk => {
      stdout += chunk
    })
    child.stderr.on('data', chunk => {
      stderr += chunk
    })
    child.on('error', error => {
      resolve({ index, total, bucket, elapsedMs: Date.now() - started, error, stdout, stderr })
    })
    child.on('close', (code, signal) => {
      resolve({ index, total, bucket, elapsedMs: Date.now() - started, code, signal, stdout, stderr })
    })
  })
}

function printFormatterOutput(result) {
  const output = `${result.stdout || ''}${result.stderr || ''}`.trim()
  if (output) console.error(output)
}

async function runFormatCheck(root, buckets) {
  const started = Date.now()
  const results = await Promise.all(buckets.map((bucket, index) => runFormatter(root, bucket, index + 1, buckets.length)))
  let failed = false
  for (const result of results) {
    const seconds = (result.elapsedMs / 1000).toFixed(3)
    const status = result.error ? 'error' : result.code === 0 ? 'ok' : `exit=${result.code}${result.signal ? ` signal=${result.signal}` : ''}`
    console.log(
      `[guard:hx-format] chunk ${result.index}/${result.total} ${status} files=${result.bucket.files.length} lines=${result.bucket.lines} elapsed=${seconds}s`
    )
    if (result.error || result.code !== 0) {
      failed = true
      if (result.error) console.error(`[guard:hx-format] ERROR: ${result.error.message}`)
      printFormatterOutput(result)
    }
  }
  if (failed) process.exit(1)
  return Date.now() - started
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
  const buckets = balancedBuckets(files, jobs)

  console.log(`[guard:hx-format] Checking Haxe formatting with jobs=${buckets.length} files=${files.length} lines=${totalLines}...`)
  const elapsedMs = await runFormatCheck(root, buckets)
  checkSentinelDeterminism(root)
  console.log(`[guard:hx-format] OK: Haxe formatting is clean. elapsed=${(elapsedMs / 1000).toFixed(3)}s`)
}

main().catch(error => fail(error && error.stack ? error.stack : String(error)))
