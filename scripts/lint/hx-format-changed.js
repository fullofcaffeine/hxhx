#!/usr/bin/env node
'use strict'

const fs = require('fs')
const path = require('path')
const { spawnSync } = require('child_process')

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
  node scripts/lint/hx-format-changed.js --write packages/foo/Bar.hx`)
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

function formatterAvailable(root) {
  const result = spawnSync('haxelib', ['run', 'formatter', '--help'], {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe']
  })
  if (result.error) fail(`haxelib is required: ${result.error.message}`)
  if (result.status !== 0) fail('formatter haxelib is not installed; run: haxelib install formatter')
}

function runFormatter(root, files, check) {
  const args = ['run', 'formatter']
  for (const file of files) args.push('-s', path.join(root, file))
  if (check) args.push('--check')
  const started = Date.now()
  const result = spawnSync('haxelib', args, {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
    stdio: ['ignore', 'pipe', 'pipe']
  })
  const elapsed = ((Date.now() - started) / 1000).toFixed(3)
  const output = `${result.stdout || ''}${result.stderr || ''}`.trim()
  if (output) console.error(output)
  if (result.error) fail(`formatter failed: ${result.error.message}`)
  if (result.status !== 0) fail(`formatter ${check ? 'check' : 'write'} failed after ${elapsed}s`)
  console.log(`[hx-format-changed] ${check ? 'checked' : 'formatted'} files=${files.length} elapsed=${elapsed}s`)
}

function main() {
  const root = repoRoot()
  process.chdir(root)
  const options = parseArgs(process.argv.slice(2))
  const files = changedFiles(root, options).filter(file => fs.existsSync(path.join(root, file)))
  if (files.length === 0) {
    console.log('[hx-format-changed] no changed Haxe files')
    return
  }
  formatterAvailable(root)
  console.log(`[hx-format-changed] ${options.check ? 'checking' : 'formatting'} changed Haxe files=${files.length}`)
  runFormatter(root, files, options.check)
}

main()
