#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const cp = require('child_process')
const { SUITES, listUniqueSuiteDependencies } = require('./upstream-suite-config')

function fail(message) {
  console.error(`[full1-suite-deps] ERROR: ${message}`)
  process.exit(1)
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

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    suites: ['server', 'display', 'threads'],
    repoPath: '.artifacts/full1/suites/haxelib_repo',
    summaryPath: '.artifacts/full1/suites/haxelib_repo.summary.json',
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--root') {
      out.root = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--suites') {
      out.suites = String(argv[i + 1] || '')
        .split(',')
        .map((suite) => suite.trim().toLowerCase())
        .filter((suite) => suite.length > 0)
      i += 1
      continue
    }
    if (arg === '--repo-path') {
      out.repoPath = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    if (arg === '--summary-path') {
      out.summaryPath = String(argv[i + 1] || '').trim()
      i += 1
      continue
    }
    fail(`unknown argument: ${arg}`)
  }

  if (out.suites.length === 0) {
    fail('missing suites for dependency preparation')
  }
  for (const suite of out.suites) {
    if (!(suite in SUITES)) {
      fail(`unsupported suite "${suite}"`)
    }
  }

  out.root = path.resolve(out.root)
  out.repoPath = path.resolve(out.root, out.repoPath)
  out.summaryPath = path.resolve(out.root, out.summaryPath)
  return out
}

function parseHaxelibPathLines(outputText) {
  return String(outputText || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
}

function probeInstalled(haxelibBin, dep, env, cwd) {
  const probe = runCommand(haxelibBin, ['--always', 'path', dep.name], { cwd, env })
  if (probe.status !== 0) {
    return false
  }
  const lines = parseHaxelibPathLines(probe.stdout || '')
  if (lines.length === 0) {
    return false
  }
  if (lines.some((line) => /^-lib\s+\S+\s+is missing\b/.test(line))) {
    return false
  }
  return true
}

function installDependency(haxelibBin, dep, env, cwd) {
  const args = ['--always', 'git', dep.name, dep.repo]
  if (dep.ref) {
    args.push(dep.ref)
  }

  let lastResult = null
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const result = runCommand(haxelibBin, args, { cwd, env })
    lastResult = result
    if (result.status === 0 && probeInstalled(haxelibBin, dep, env, cwd)) {
      return
    }
    const retryMessage = result.stderr || result.stdout || `exit=${result.status}`
    console.error(`[full1-suite-deps] install retry ${attempt}/3 for ${dep.name}: ${retryMessage}`)
  }

  const errText = `${lastResult && lastResult.stdout ? lastResult.stdout : ''}${lastResult && lastResult.stderr ? lastResult.stderr : ''}`
  fail(`failed to install dependency ${dep.name}\n${errText}`)
}

function main() {
  const parsed = parseArgs(process.argv.slice(2))
  const cwd = parsed.root
  const haxelibBin = String(process.env.HAXELIB_BIN || '').trim() || 'haxelib'
  ensureDir(parsed.repoPath)
  ensureDir(path.dirname(parsed.summaryPath))

  const env = {
    ...process.env,
    HAXELIB_PATH: parsed.repoPath,
  }
  const deps = listUniqueSuiteDependencies(parsed.suites)
  const installed = []

  for (const dep of deps) {
    if (!probeInstalled(haxelibBin, dep, env, cwd)) {
      installDependency(haxelibBin, dep, env, cwd)
    }
    installed.push({
      name: dep.name,
      repo: dep.repo,
      ref: dep.ref || '',
    })
  }

  fs.writeFileSync(parsed.summaryPath, `${JSON.stringify({
    schema: 'full1-suite-haxelib-prep.v1',
    repo_path: parsed.repoPath,
    suites: parsed.suites,
    deps: installed,
  }, null, 2)}\n`, 'utf8')
}

main()
