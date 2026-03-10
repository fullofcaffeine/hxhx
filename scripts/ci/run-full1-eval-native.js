#!/usr/bin/env node
/**
 * run-full1-eval-native.js
 *
 * Full1 strict native eval/interp runner.
 *
 * Why:
 * - Full1 needs a direct, non-delegating eval/interp evidence lane.
 * - The current upstream-aligned entrypoint is `tests/unit/compile-macro.hxml`,
 *   which already exercises `--interp`-style behavior through the native Gate1 path.
 *
 * What:
 * - Runs `scripts/hxhx/run-upstream-unit-macro-native.sh` with strict stage0-forbidden env.
 * - Writes deterministic stdout/stderr logs plus a summary JSON.
 * - Emits `FULL1_EVAL_NATIVE:PASS` on success.
 *
 * How:
 * - Treat upstream Haxe 4.3.7 as the behavioral authority.
 * - Reuse the existing native Gate1 runner instead of inventing a custom eval harness.
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

function fail(message) {
  console.error(`[full1-eval-native] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    upstreamDir: '',
    artifactsDir: '.artifacts/full1/eval-native',
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
    fail(`unknown argument: ${arg}`)
  }

  out.root = path.resolve(out.root)
  out.upstreamDir = out.upstreamDir
    ? path.resolve(out.root, out.upstreamDir)
    : path.join(out.root, 'vendor/haxe')
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function writeFile(filePath, contents) {
  fs.writeFileSync(filePath, contents, 'utf8')
}

function run(command, args, options) {
  return cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64,
  })
}

function main() {
  const startedAt = new Date()
  const parsed = parseArgs(process.argv.slice(2))

  if (!fs.existsSync(path.join(parsed.upstreamDir, 'tests/unit/compile-macro.hxml'))) {
    fail(`missing upstream eval entrypoint at ${path.join(parsed.upstreamDir, 'tests/unit/compile-macro.hxml')}`)
  }

  ensureDir(parsed.artifactsDir)
  const stdoutPath = path.join(parsed.artifactsDir, 'full1-eval-native.stdout.log')
  const stderrPath = path.join(parsed.artifactsDir, 'full1-eval-native.stderr.log')
  const summaryPath = path.join(parsed.artifactsDir, 'full1-eval-native.summary.json')

  const env = { ...process.env }
  env.HAXE_UPSTREAM_DIR = parsed.upstreamDir
  env.HXHX_FORBID_STAGE0 = env.HXHX_FORBID_STAGE0 || '1'
  delete env.HXHX_ALLOW_STAGE0
  const hxhxBin = String(env.HXHX_BIN || '').trim()

  const command = ['bash', 'scripts/hxhx/run-upstream-unit-macro-native.sh']
  const result = run(command[0], command.slice(1), { cwd: parsed.root, env })

  writeFile(stdoutPath, result.stdout || '')
  writeFile(stderrPath, result.stderr || '')

  const endedAt = new Date()
  const summary = {
    schema: 'full1-eval-native-summary.v1',
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
    duration_ms: endedAt.getTime() - startedAt.getTime(),
    root: parsed.root,
    upstream_dir: parsed.upstreamDir,
    workflow_mode: 'full1-eval-native',
    eval_context: {
      entrypoint: 'tests/unit/compile-macro.hxml',
      command,
      stage0_forbidden: env.HXHX_FORBID_STAGE0 === '1',
      macro_runtime_mode: String(env.HXHX_MACRO_RUNTIME_MODE || 'default(inproc)'),
      hxhx_bin: hxhxBin || null,
    },
    result: {
      exit_code: result.status == null ? -1 : result.status,
      signal: result.signal || null,
      error: result.error ? String(result.error.message || result.error) : '',
    },
    logs: {
      stdout: path.relative(parsed.root, stdoutPath),
      stderr: path.relative(parsed.root, stderrPath),
    },
    marker: result.status === 0 ? 'FULL1_EVAL_NATIVE:PASS' : 'FULL1_EVAL_NATIVE:FAIL',
  }
  writeFile(summaryPath, `${JSON.stringify(summary, null, 2)}\n`)

  console.log(`[full1-eval-native] summary=${summaryPath}`)
  if (result.status === 0) {
    console.log('FULL1_EVAL_NATIVE:PASS')
    return
  }

  console.error('FULL1_EVAL_NATIVE:FAIL')
  process.exit(result.status == null ? 1 : result.status)
}

main()
