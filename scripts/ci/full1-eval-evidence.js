#!/usr/bin/env node
/**
 * Measure native eval/interp compiler latency for Full1 perf evidence.
 *
 * This runner compares upstream Haxe's `tests/unit/compile-macro.hxml` against a
 * stage0-free hxhx Stage3 no-emit macro/typer invocation. The full native
 * eval runner is still executed once as the correctness marker source, but the
 * measured `compile_wall_ms` samples deliberately exclude target OCaml
 * emit/build/run time. It writes evaluator-ready
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

function lastNonEmptyLine(text) {
  const lines = String(text || '').trim().split(/\r?\n/).filter(Boolean)
  return lines.length > 0 ? lines[lines.length - 1].trim() : ''
}

function resolveExecutable(root, maybePath) {
  const text = String(maybePath || '').trim()
  if (!text) return ''
  return path.isAbsolute(text) ? text : path.resolve(root, text)
}

function isExecutable(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.X_OK)
    return true
  } catch (_) {
    return false
  }
}

function resolveHxhxRunner(parsed, env) {
  let hxhxBin = resolveExecutable(parsed.root, env.HXHX_BIN || '')
  if (!hxhxBin || !fs.existsSync(hxhxBin)) {
    const result = run('bash', ['scripts/hxhx/build-hxhx.sh'], { cwd: parsed.root, env })
    writeLog(path.join(parsed.artifactsDir, 'build-hxhx'), 'build-hxhx', result)
    if (result.status !== 0) fail(`failed to build hxhx for eval evidence (exit=${result.status})`)
    hxhxBin = lastNonEmptyLine(result.stdout)
  }
  if (!hxhxBin || !fs.existsSync(hxhxBin)) {
    fail(`hxhx build did not produce a valid binary path: ${hxhxBin || '<empty>'}`)
  }
  env.HXHX_BIN = hxhxBin
  if (isExecutable(hxhxBin)) return { command: hxhxBin, args: [], bin: hxhxBin }
  return { command: 'ocamlrun', args: [hxhxBin], bin: hxhxBin }
}

function ensureMacroHost(parsed, env) {
  let macroHost = resolveExecutable(parsed.root, env.HXHX_MACRO_HOST_EXE || '')
  if (!macroHost || !fs.existsSync(macroHost)) {
    const result = run('bash', ['scripts/hxhx/build-hxhx-macro-host.sh'], { cwd: parsed.root, env })
    writeLog(path.join(parsed.artifactsDir, 'build-hxhx-macro-host'), 'build-hxhx-macro-host', result)
    if (result.status !== 0) fail(`failed to build hxhx macro host for eval evidence (exit=${result.status})`)
    macroHost = lastNonEmptyLine(result.stdout)
  }
  if (!macroHost || !fs.existsSync(macroHost)) {
    fail(`hxhx macro-host build did not produce a valid binary path: ${macroHost || '<empty>'}`)
  }
  env.HXHX_MACRO_HOST_EXE = macroHost
  return macroHost
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
  const pathLines = parseHaxelibPathLines(probe.stdout || '')
  writeTemporaryLibraryHxml(parsed.root, 'utest', pathLines)
  writeTemporaryLibraryHxml(path.join(parsed.upstreamDir, 'tests/unit'), 'utest', pathLines)
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
  const hxhxEnv = {
    ...env,
    HAXE_BIN: '__hxhx_stage0_disabled__',
    HXHX_FORBID_STAGE0: '1',
    HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES: env.HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES || '1'
  }
  delete hxhxEnv.HXHX_ALLOW_STAGE0
  delete hxhxEnv.HXHX_FORCE_STAGE0
  delete hxhxEnv.HXHX_MACRO_HOST_FORCE_STAGE0
  delete hxhxEnv.HXHX_MACRO_HOST_ENTRYPOINTS
  delete hxhxEnv.HXHX_MACRO_HOST_EXTRA_CP
  delete hxhxEnv.HXHX_EXPR_MACROS

  if (!hxhxEnv.HAXE_STD_PATH && fs.existsSync(path.join(parsed.upstreamDir, 'std'))) {
    hxhxEnv.HAXE_STD_PATH = path.join(parsed.upstreamDir, 'std')
  }

  const runner = resolveHxhxRunner(parsed, hxhxEnv)
  ensureMacroHost(parsed, hxhxEnv)
  const cwd = path.join(parsed.upstreamDir, 'tests/unit')
  for (let rep = 1; rep <= parsed.reps; rep += 1) {
    const artifactsDir = path.join(parsed.artifactsDir, `hxhx-${rep}`)
    const outDir = path.join(artifactsDir, 'stage3-no-emit-out')
    fs.rmSync(outDir, { recursive: true, force: true })
    ensureDir(outDir)
    const result = run(
      runner.command,
      [
        ...runner.args,
        '--hxhx-stage3',
        '--hxhx-no-emit',
        'compile-macro.hxml',
        '--hxhx-out',
        outDir
      ],
      { cwd, env: hxhxEnv }
    )
    writeLog(artifactsDir, 'stage3-no-emit', result)
    if (result.status !== 0) fail(`hxhx eval rep ${rep} failed (exit=${result.status})`)
    const stdout = String(result.stdout || '')
    if (!/^macro_run\[0\]=ok$/m.test(stdout)) fail(`hxhx eval rep ${rep} did not report macro_run[0]=ok`)
    if (!/^hook_onGenerate\[0\]=ok$/m.test(stdout)) fail(`hxhx eval rep ${rep} did not report hook_onGenerate[0]=ok`)
    if (!/^stage3=no_emit_ok$/m.test(stdout)) fail(`hxhx eval rep ${rep} did not report stage3=no_emit_ok`)
    values.push(result.durationMs)
  }
  return values
}

function verifyNativeEvalMarker(parsed, env) {
  const artifactsDir = path.join(parsed.artifactsDir, 'native-marker')
  const result = run(
    process.execPath,
    ['scripts/ci/run-full1-eval-native.js', '--upstream-dir', parsed.upstreamDir, '--artifacts-dir', artifactsDir],
    { cwd: parsed.root, env }
  )
  writeLog(artifactsDir, 'runner', result)
  if (result.status !== 0) fail(`native eval marker verification failed (exit=${result.status})`)
  if (!/FULL1_EVAL_NATIVE:PASS/.test(`${result.stdout || ''}\n${result.stderr || ''}`)) {
    fail('native eval marker verification did not emit FULL1_EVAL_NATIVE:PASS')
  }
}

function main() {
  const parsed = parseArgs(process.argv.slice(2))
  ensureDir(parsed.artifactsDir)
  ensureDir(path.dirname(parsed.jsonOut))
  const upstreamHxml = path.join(parsed.upstreamDir, 'tests/unit/compile-macro.hxml')
  if (!fs.existsSync(upstreamHxml)) fail(`missing upstream eval hxml: ${upstreamHxml}`)
  const env = {
    ...process.env,
    HAXE_UPSTREAM_DIR: parsed.upstreamDir,
    HXHX_FORBID_STAGE0: '1'
  }
  delete env.HXHX_ALLOW_STAGE0
  ensureUtest(parsed, env)
  // Resolve shared bootstrap binaries in the parent process so the correctness
  // marker and measured compiler samples do not perform duplicate builds.
  resolveHxhxRunner(parsed, env)
  ensureMacroHost(parsed, env)

  verifyNativeEvalMarker(parsed, env)
  const upstreamValues = measureUpstream(parsed, env)
  const hxhxValues = measureHxhx(parsed, env)
  const evidence = {
    schema: 'full1-perf-evidence.v1',
    haxeCompatibilityBaseline: '4.3.7',
    runner: {
      source: 'scripts/ci/full1-eval-evidence.js',
      upstreamEntrypoint: 'tests/unit/compile-macro.hxml',
      hxhxMeasuredEntrypoint: 'hxhx --hxhx-stage3 --hxhx-no-emit tests/unit/compile-macro.hxml',
      nativeMarkerVerification: 'scripts/ci/run-full1-eval-native.js',
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
