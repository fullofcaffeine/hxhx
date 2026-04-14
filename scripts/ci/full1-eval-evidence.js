#!/usr/bin/env node
/**
 * Measure native eval/interp latency for Full1 perf evidence.
 *
 * This runner compares upstream Haxe's `tests/unit/compile-macro.hxml` against
 * the stage0-free native hxhx eval runner. It writes evaluator-ready
 * full1-perf-evidence.v1 JSON for the `full1-native-eval-latency` workload.
 */

const fs = require('fs')
const path = require('path')
const cp = require('child_process')

const cleanupFiles = []

process.on('exit', () => {
  for (const filePath of cleanupFiles) {
    try {
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath)
    } catch (_) {
      // Best-effort cleanup only; the original test failure should remain visible.
    }
  }
})

function fail(message, code = 2) {
  console.error(`[full1-eval-evidence] ERROR: ${message}`)
  process.exit(code)
}

function usage() {
  console.error(`Usage: node scripts/ci/full1-eval-evidence.js --json-out <evidence.json>

Options:
  --artifacts-dir <path>  Directory for per-repetition logs
  --json-out <path>       Full1 perf evidence JSON output path
  --reps <n>              Measured repetitions (default: FULL1_PERF_REPS or 5)
  --root <path>           Repository root (default: cwd)
  --upstream-dir <path>   Haxe upstream checkout (default: vendor/haxe)
`)
}

function positiveInt(value, owner) {
  if (!/^[1-9][0-9]*$/.test(String(value || ''))) fail(`${owner} must be a positive integer`)
  return Number(value)
}

function parseArgs(argv) {
  const out = {
    root: process.cwd(),
    upstreamDir: '',
    artifactsDir: '.artifacts/full1/perf/eval-native',
    jsonOut: '',
    reps: positiveInt(process.env.FULL1_PERF_REPS || '5', 'FULL1_PERF_REPS')
  }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--root') {
      i += 1
      out.root = argv[i] || ''
    } else if (arg === '--upstream-dir') {
      i += 1
      out.upstreamDir = argv[i] || ''
    } else if (arg === '--artifacts-dir') {
      i += 1
      out.artifactsDir = argv[i] || ''
    } else if (arg === '--json-out') {
      i += 1
      out.jsonOut = argv[i] || ''
    } else if (arg === '--reps') {
      i += 1
      out.reps = positiveInt(argv[i], '--reps')
    } else if (arg === '--help' || arg === '-h') {
      usage()
      process.exit(0)
    } else {
      fail(`unknown argument: ${arg}`)
    }
  }
  if (!out.jsonOut) fail('--json-out is required')
  out.root = path.resolve(out.root)
  out.upstreamDir = out.upstreamDir ? path.resolve(out.root, out.upstreamDir) : path.join(out.root, 'vendor/haxe')
  out.artifactsDir = path.resolve(out.root, out.artifactsDir)
  out.jsonOut = path.resolve(out.root, out.jsonOut)
  return out
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function run(command, args, options) {
  const started = process.hrtime.bigint()
  const result = cp.spawnSync(command, args, {
    cwd: options.cwd,
    env: options.env,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 64
  })
  const ended = process.hrtime.bigint()
  return {
    ...result,
    durationMs: Number((ended - started) / 1000000n)
  }
}

function writeLog(dir, name, result) {
  ensureDir(dir)
  fs.writeFileSync(path.join(dir, `${name}.stdout.log`), result.stdout || '', 'utf8')
  fs.writeFileSync(path.join(dir, `${name}.stderr.log`), result.stderr || '', 'utf8')
}

function parseHaxelibPathLines(outputText) {
  return String(outputText || '')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line.length > 0)
}

function haxelibPathToHxmlLines(lines, lib) {
  const out = []
  for (const line of lines) {
    if (/^-lib\s+\S+\s+is missing\b/.test(line)) {
      fail(`haxelib path ${lib} reported missing library: ${line}`)
    }
    if (
      line.startsWith('-D ')
      || line.startsWith('--macro ')
      || line.startsWith('-cp ')
      || line.startsWith('--class-path ')
      || line.startsWith('-')
    ) {
      out.push(line)
      continue
    }
    out.push(`-cp ${line}`)
  }
  if (out.length === 0) fail(`haxelib path ${lib} produced no usable hxml lines`)
  return out
}

function writeTemporaryLibraryHxml(root, lib, lines) {
  const hxmlDir = path.join(root, 'haxe_libraries')
  const hxmlPath = path.join(hxmlDir, `${lib}.hxml`)
  if (fs.existsSync(hxmlPath)) return
  ensureDir(hxmlDir)
  fs.writeFileSync(hxmlPath, haxelibPathToHxmlLines(lines, lib).join('\n') + '\n', 'utf8')
  cleanupFiles.push(hxmlPath)
}

function ensureUtest(parsed, env) {
  const haxelib = env.HAXELIB_BIN || 'haxelib'
  const list = run(haxelib, ['list'], { cwd: parsed.root, env })
  if (list.status !== 0 || !/^utest:/m.test(list.stdout || '')) {
    const install = run(
      haxelib,
      ['--always', 'git', 'utest', 'https://github.com/haxe-utest/utest', 'a94f8812e8786f2b5fec52ce9f26927591d26327'],
      { cwd: parsed.root, env }
    )
    if (install.status !== 0) {
      writeLog(parsed.artifactsDir, 'utest-install', install)
      fail(`failed to install pinned utest dependency (exit=${install.status})`)
    }
  }
  const probe = run(haxelib, ['--always', 'path', 'utest'], { cwd: parsed.root, env })
  writeLog(parsed.artifactsDir, 'utest-path', probe)
  if (probe.status !== 0) fail(`failed to resolve pinned utest dependency path (exit=${probe.status})`)
  writeTemporaryLibraryHxml(parsed.root, 'utest', parseHaxelibPathLines(probe.stdout || ''))
}

function measureUpstream(parsed, env) {
  const cwd = path.join(parsed.upstreamDir, 'tests/unit')
  const hxml = path.join(cwd, 'compile-macro.hxml')
  if (!fs.existsSync(hxml)) fail(`missing upstream eval hxml: ${hxml}`)
  const values = []
  for (let rep = 1; rep <= parsed.reps; rep += 1) {
    const result = run('haxe', ['compile-macro.hxml'], { cwd, env })
    writeLog(path.join(parsed.artifactsDir, `upstream-${rep}`), 'compile-macro', result)
    if (result.status !== 0) fail(`upstream_haxe eval rep ${rep} failed (exit=${result.status})`)
    values.push(result.durationMs)
  }
  return values
}

function measureHxhx(parsed, env) {
  const values = []
  for (let rep = 1; rep <= parsed.reps; rep += 1) {
    const artifactsDir = path.join(parsed.artifactsDir, `hxhx-${rep}`)
    const result = run(
      process.execPath,
      ['scripts/ci/run-full1-eval-native.js', '--upstream-dir', parsed.upstreamDir, '--artifacts-dir', artifactsDir],
      { cwd: parsed.root, env }
    )
    writeLog(artifactsDir, 'runner', result)
    if (result.status !== 0) fail(`hxhx eval rep ${rep} failed (exit=${result.status})`)
    values.push(result.durationMs)
  }
  return values
}

function main() {
  const parsed = parseArgs(process.argv.slice(2))
  ensureDir(parsed.artifactsDir)
  ensureDir(path.dirname(parsed.jsonOut))
  const env = {
    ...process.env,
    HAXE_UPSTREAM_DIR: parsed.upstreamDir,
    HXHX_FORBID_STAGE0: '1'
  }
  delete env.HXHX_ALLOW_STAGE0
  ensureUtest(parsed, env)

  const upstreamValues = measureUpstream(parsed, env)
  const hxhxValues = measureHxhx(parsed, env)
  const evidence = {
    schema: 'full1-perf-evidence.v1',
    haxeCompatibilityBaseline: '4.3.7',
    runner: {
      source: 'scripts/ci/full1-eval-evidence.js',
      upstreamEntrypoint: 'tests/unit/compile-macro.hxml',
      reps: parsed.reps
    },
    git: {
      sha: process.env.GITHUB_SHA || null,
      ref: process.env.GITHUB_REF || null,
      run_id: process.env.GITHUB_RUN_ID || null,
      run_attempt: process.env.GITHUB_RUN_ATTEMPT || null
    },
    workloads: [
      {
        id: 'full1-native-eval-latency',
        samples: [
          {
            metric: 'compile_wall_ms',
            lane: 'upstream_haxe',
            values: upstreamValues
          },
          {
            metric: 'compile_wall_ms',
            lane: 'hxhx',
            values: hxhxValues
          }
        ]
      }
    ]
  }
  fs.writeFileSync(parsed.jsonOut, JSON.stringify(evidence, null, 2) + '\n')
  console.log(`[full1-eval-evidence] evidence=${parsed.jsonOut}`)
}

main()
