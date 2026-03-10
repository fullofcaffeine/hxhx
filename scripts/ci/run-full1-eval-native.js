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

function latestMtimeMs(root) {
  if (!fs.existsSync(root)) return 0
  let latest = 0
  const stack = [root]
  while (stack.length > 0) {
    const current = stack.pop()
    const stat = fs.statSync(current)
    if (stat.mtimeMs > latest) latest = stat.mtimeMs
    if (!stat.isDirectory()) continue
    for (const name of fs.readdirSync(current))
      stack.push(path.join(current, name))
  }
  return latest
}

function latestMtimeMsMany(paths) {
  let latest = 0
  for (const current of paths) {
    const value = latestMtimeMs(current)
    if (value > latest) latest = value
  }
  return latest
}

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

function resolveExecutable(root, maybePath) {
  const text = String(maybePath || '').trim()
  if (!text) return ''
  if (path.isAbsolute(text)) return text
  return path.resolve(root, text)
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

function resolveCachedHxhxBin(root) {
  const buildDir = path.join(root, '.tmp/full1-eval-native-hxhx')
  const candidates = [
    path.join(buildDir, '_build/default/out.bc'),
    path.join(buildDir, '_build/default/out.exe'),
  ]
  const cached = candidates.find((candidate) => fs.existsSync(candidate))
  if (!cached) {
    return { buildDir, bin: '' }
  }

  const bootstrapMtime = latestMtimeMs(path.join(root, 'packages/hxhx/bootstrap_out'))
  const sourceMtime = latestMtimeMsMany([
    path.join(root, 'packages/hxhx/src'),
    path.join(root, 'packages/hxhx-core/src'),
    path.join(root, 'packages/reflaxe.ocaml/src'),
    path.join(root, 'packages/reflaxe.ocaml/std'),
    path.join(root, 'scripts/hxhx/build-hxhx.sh'),
  ])
  const cachedMtime = fs.statSync(cached).mtimeMs
  if (cachedMtime < bootstrapMtime)
    return { buildDir, bin: '' }
  if (cachedMtime < sourceMtime)
    return { buildDir, bin: '' }
  return { buildDir, bin: cached }
}

function buildCachedHxhxBin(root, env, buildDir) {
  ensureDir(path.dirname(buildDir))
  const buildEnv = {
    ...env,
    HXHX_BOOTSTRAP_BUILD_DIR: buildDir,
    // Local/native eval diagnosis should prefer the byte bootstrap path by default.
    // The native bootstrap path is still valuable, but it is too expensive and too
    // stall-prone around EmitterStage.ml to be the default feedback loop here.
    HXHX_BOOTSTRAP_PREFER_NATIVE: env.HXHX_BOOTSTRAP_PREFER_NATIVE || '0',
  }
  const result = run('bash', ['scripts/hxhx/build-hxhx.sh'], { cwd: root, env: buildEnv })
  if (result.status !== 0) {
    const stdout = String(result.stdout || '')
    const stderr = String(result.stderr || '')
    throw new Error(`failed to build cached HXHX_BIN (exit=${result.status})\n${stdout}\n${stderr}`)
  }
  const lines = String(result.stdout || '').trim().split(/\r?\n/).filter(Boolean)
  const resolved = lines.length > 0 ? lines[lines.length - 1].trim() : ''
  if (!resolved || !fs.existsSync(resolved))
    throw new Error(`cached HXHX_BIN build did not produce a valid path: ${resolved || '<empty>'}`)
  return resolved
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
  let hxhxBin = resolveExecutable(parsed.root, env.HXHX_BIN || '')
  if (hxhxBin.length === 0) {
    const cached = resolveCachedHxhxBin(parsed.root)
    hxhxBin = cached.bin || buildCachedHxhxBin(parsed.root, env, cached.buildDir)
  }
  env.HXHX_BIN = hxhxBin

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
