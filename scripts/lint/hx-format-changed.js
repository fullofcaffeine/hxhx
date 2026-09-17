#!/usr/bin/env node
'use strict'

const fs = require('fs')
const path = require('path')
const os = require('os')
const { spawnSync } = require('child_process')
const { runCommandWithTimeout } = require('./hx-format-guard.js')

/**
 * Formats or checks only changed Haxe files with the official haxelib formatter.
 *
 * Why this exists:
 * - `npm run guard:hx-format` is the full repo guard and remains the CI/release
 *   source of truth.
 * - Local edit loops usually touch a handful of `.hx` files, so running the
 *   formatter on only those files gives faster feedback without inventing a
 *   second style rule.
 */

function fail(message) {
  console.error(`[hx-format-changed] ERROR: ${message}`)
  process.exit(1)
}

function usage() {
  console.log(`Usage: node scripts/lint/hx-format-changed.js [--check|--write] [--staged] [--base <ref>] [file ...]

Default file set:
  tracked .hx files changed against HEAD, plus untracked .hx files.

Examples:
  npm run format:hx:changed
  npm run guard:hx-format:changed
  node scripts/lint/hx-format-changed.js --check --staged
  node scripts/lint/hx-format-changed.js --write packages/foo/Bar.hx

HX_FORMAT_TIMEOUT_SECONDS bounds the formatter process tree (default: 240).
Timeout returns 124; interruption returns 130 or 143.
On POSIX, timeout and interruption stop the complete formatter process group.`)
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

function parseArgs(argv) {
  const options = {
    check: false,
    write: false,
    staged: false,
    base: process.env.HX_FORMAT_BASE || 'HEAD',
    files: []
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--help' || arg === '-h') {
      usage()
      process.exit(0)
    } else if (arg === '--check') {
      options.check = true
    } else if (arg === '--write') {
      options.write = true
    } else if (arg === '--staged') {
      options.staged = true
    } else if (arg === '--base') {
      i += 1
      if (i >= argv.length) fail('--base requires a git revision')
      options.base = argv[i]
    } else if (arg === '--') {
      options.files.push(...argv.slice(i + 1))
      break
    } else if (arg.startsWith('--')) {
      fail(`unknown option: ${arg}`)
    } else {
      options.files.push(arg)
    }
  }
  if (options.check && options.write) fail('choose only one of --check or --write')
  if (!options.check && !options.write) options.write = true
  return options
}

function normalizeFile(root, file) {
  const relative = path.isAbsolute(file) ? path.relative(root, file) : file
  return relative.split(path.sep).join('/')
}

function isEligibleHaxeFile(file) {
  return file.endsWith('.hx') && !/(^|\/)(deps|out|bootstrap_work|bootstrap_verify)\//.test(file)
}

function uniqueSorted(files) {
  return Array.from(new Set(files)).sort((a, b) => a.localeCompare(b))
}

function changedFiles(root, options) {
  if (options.files.length > 0) {
    return uniqueSorted(options.files.map(file => normalizeFile(root, file)).filter(isEligibleHaxeFile))
  }

  const trackedArgs = options.staged
    ? ['diff', '--cached', '--name-only', '--diff-filter=ACMR', '--', '*.hx']
    : ['diff', '--name-only', '--diff-filter=ACMR', options.base, '--', '*.hx']
  const tracked = commandOutput('git', trackedArgs, { cwd: root }).split(/\r?\n/).filter(Boolean)
  const untracked = options.staged
    ? []
    : commandOutput('git', ['ls-files', '--others', '--exclude-standard', '--', '*.hx'], { cwd: root })
        .split(/\r?\n/)
        .filter(Boolean)
  return uniqueSorted(tracked.concat(untracked).map(file => normalizeFile(root, file)).filter(isEligibleHaxeFile))
}

/** Keep one formatter tree attached until it exits or cancellation stops it. */
async function runFormatter(root, files, check) {
  const timeoutSeconds = Number(process.env.HX_FORMAT_TIMEOUT_SECONDS || '240')
  if (!Number.isInteger(timeoutSeconds) || timeoutSeconds <= 0) fail('HX_FORMAT_TIMEOUT_SECONDS must be a positive integer')
  const args = ['run', 'formatter']
  for (const file of files) args.push('-s', path.join(root, file))
  if (check) args.push('--check')
  const controller = new AbortController()
  let interruptedCode = 0
  const stop = code => {
    if (interruptedCode === 0) interruptedCode = code
    controller.abort()
  }
  const interrupt = () => stop(130)
  const terminate = () => stop(143)
  process.on('SIGINT', interrupt)
  process.on('SIGTERM', terminate)
  let result
  try {
    result = await runCommandWithTimeout('haxelib', args, {
      cwd: root,
      timeoutMs: timeoutSeconds * 1000,
      signal: controller.signal,
      captureOutput: false,
      onStdout: text => process.stdout.write(text),
      onStderr: text => process.stderr.write(text)
    })
  } finally {
    process.removeListener('SIGINT', interrupt)
    process.removeListener('SIGTERM', terminate)
  }
  const elapsed = (result.elapsedMs / 1000).toFixed(3)
  let code = result.code
  if (interruptedCode) code = interruptedCode
  else if (result.timedOut) code = 124
  else if (result.error) code = 127
  else if (code === null) code = os.constants.signals[result.signal] ? 128 + os.constants.signals[result.signal] : 1
  if (result.error) console.error(`[hx-format-changed] formatter failed: ${result.error.message}`)
  console.error(`[hx-format-changed] ${code === 0 ? (check ? 'checked' : 'formatted') : 'stopped'} files=${files.length} elapsed=${elapsed}s exit=${code}`)
  process.exitCode = code
}

async function main() {
  const root = repoRoot()
  process.chdir(root)
  const options = parseArgs(process.argv.slice(2))
  const files = changedFiles(root, options).filter(file => fs.existsSync(path.join(root, file)))
  if (files.length === 0) {
    console.error('[hx-format-changed] no changed Haxe files')
    return
  }
  console.error(`[hx-format-changed] ${options.check ? 'checking' : 'formatting'} changed Haxe files=${files.length}`)
  await runFormatter(root, files, options.check)
}

main().catch(error => fail(error.message))
