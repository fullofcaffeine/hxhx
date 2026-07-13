#!/usr/bin/env node
/**
 * Synthetic contract tests for same-run bytecode/native KPI comparisons.
 */

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = process.cwd()
const comparator = path.join(repoRoot, 'scripts/ci/hxhx-kpi-artifact-comparison.js')

function fail(message) {
  console.error(`[hxhx-kpi-artifact-comparison-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function metric(name, lane, unit, samples) {
  return {
    metric: name,
    lane,
    unit,
    summary: {
      count: samples.length,
      min: Math.min(...samples),
      max: Math.max(...samples),
      mean: samples.reduce((sum, value) => sum + value, 0) / samples.length,
      median: samples[0],
      p95: Math.max(...samples),
      samples
    }
  }
}

function validReport(kind) {
  const isNative = kind === 'native-executable'
  return {
    schema: 'hxhx.kpi.v2',
    generated_at_utc: isNative ? '2026-07-13T00:02:00.000Z' : '2026-07-13T00:00:00.000Z',
    git: {
      commit: '0123456789abcdef0123456789abcdef01234567',
      tracked_source_clean: true
    },
    config: {
      reps: 2,
      run_macro_lane: true
    },
    environment: {
      platform: 'Linux-test',
      os: 'Linux',
      os_release: 'test',
      architecture: 'x86_64',
      cpu_model: 'fixture cpu',
      python_version: '3.13.0',
      haxe_bin: 'haxe',
      haxe_version: '4.3.7',
      hxhx_bin: isNative ? '.tmp/native/out.exe' : '.tmp/bytecode/out.bc',
      hxhx_artifact_kind: kind,
      node_version: 'v24.0.0',
      ocaml_version: '5.2.1',
      dune_version: '3.17.0'
    },
    measurement: {
      command: 'npm run hxhx:bench:kpi',
      source: 'scripts/hxhx/bench-kpi.sh',
      repetitions: 2,
      raw_samples_embedded: true,
      warmup_runs: {
        compile_wall_ms: 0,
        incremental_rebuild_ms: 1,
        macro_overhead_ms: 0,
        peak_rss_kb: 0
      },
      states: {
        compile_wall_ms: 'compiler invocation with a reused compiler binary',
        incremental_rebuild_ms: 'unchanged input after one unrecorded warmup invocation',
        macro_overhead_ms: 'macro-enabled time minus its paired baseline compile',
        peak_rss_kb: 'maximum resident set size for the measured compiler process tree'
      }
    },
    metrics: [
      metric('compile_wall_ms', 'ocaml_metal_builtin', 'ms', isNative ? [800, 900] : [5000, 5200]),
      metric('peak_rss_kb', 'ocaml_metal_builtin', 'kb', isNative ? [28000, 28100] : [29000, 29100])
    ],
    lane_ratios: []
  }
}

function runComparison(bytecode, native, tmpDir, label, expectedStatus, expectedSnippet = null) {
  const bytecodePath = path.join(tmpDir, `${label}.bytecode.json`)
  const nativePath = path.join(tmpDir, `${label}.native.json`)
  const outputPath = path.join(tmpDir, `${label}.comparison.json`)
  fs.writeFileSync(bytecodePath, `${JSON.stringify(bytecode, null, 2)}\n`)
  fs.writeFileSync(nativePath, `${JSON.stringify(native, null, 2)}\n`)
  const result = childProcess.spawnSync(process.execPath, [
    comparator,
    '--bytecode-report', bytecodePath,
    '--native-report', nativePath,
    '--json-out', outputPath
  ], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== expectedStatus) {
    fail(`${label}: expected exit ${expectedStatus}, got ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  if (expectedSnippet && !result.stderr.includes(expectedSnippet)) {
    fail(`${label}: missing error ${JSON.stringify(expectedSnippet)}\n${result.stderr}`)
  }
  return { outputPath, result }
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-kpi-artifact-comparison-'))
  try {
    const valid = runComparison(
      validReport('ocaml-bytecode'),
      validReport('native-executable'),
      tmpDir,
      'valid',
      0
    )
    if (!valid.result.stdout.includes('HXHX_KPI_ARTIFACT_COMPARISON:PASS')) {
      fail('valid comparison did not emit its pass marker')
    }
    const payload = JSON.parse(fs.readFileSync(valid.outputPath, 'utf8'))
    if (payload.schema !== 'hxhx.kpi-artifact-comparison.v1' || payload.diagnostic_only !== true) {
      fail('valid comparison did not preserve diagnostic-only schema semantics')
    }
    const compile = payload.metrics.find(row => row.metric === 'compile_wall_ms')
    if (!compile || compile.bytecodeMedian !== 5100 || compile.nativeMedian !== 850) {
      fail(`unexpected compile comparison: ${JSON.stringify(compile)}`)
    }

    const cases = [
      ['wrong-bytecode-kind', bytecode => { bytecode.environment.hxhx_artifact_kind = 'native-executable' }, null, 'must identify hxhx_artifact_kind as ocaml-bytecode'],
      ['native-fell-back', null, native => { native.environment.hxhx_artifact_kind = 'ocaml-bytecode' }, 'must identify hxhx_artifact_kind as native-executable'],
      ['cross-sha', null, native => { native.git.commit = 'fedcba9876543210fedcba9876543210fedcba98' }, 'same commit SHA'],
      ['different-cpu', null, native => { native.environment.cpu_model = 'different fixture cpu' }, 'same environment.cpu_model'],
      ['different-toolchain', null, native => { native.environment.ocaml_version = '5.3.0' }, 'same environment.ocaml_version'],
      ['different-config', null, native => { native.config.run_macro_lane = false }, 'same benchmark config'],
      ['missing-samples', null, native => { native.metrics[0].summary.samples = [] }, 'summary.samples must be a non-empty array'],
      ['missing-metric', null, native => { native.metrics.pop() }, 'same metric/lane rows']
    ]
    for (const [label, mutateBytecode, mutateNative, snippet] of cases) {
      const bytecode = validReport('ocaml-bytecode')
      const native = validReport('native-executable')
      if (mutateBytecode) mutateBytecode(bytecode)
      if (mutateNative) mutateNative(native)
      runComparison(bytecode, native, tmpDir, label, 1, snippet)
    }
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
  console.log('[ci:guards] OK: bytecode/native KPI comparison fixtures pass')
}

main()
