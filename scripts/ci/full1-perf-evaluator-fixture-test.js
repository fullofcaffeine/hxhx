#!/usr/bin/env node
/**
 * Synthetic fixture tests for full1-perf-evaluator.js.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const childProcess = require('child_process')

const repoRoot = process.cwd()
const evaluator = path.join(repoRoot, 'scripts/ci/full1-perf-evaluator.js')

function fail(message) {
  console.error(`[full1-perf-evaluator-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function writeJson(filePath, payload) {
  fs.writeFileSync(filePath, JSON.stringify(payload, null, 2) + '\n')
}

function evidence(workloadId, upstreamValues, hxhxValues) {
  return {
    schema: 'full1-perf-evidence.v1',
    haxeCompatibilityBaseline: '4.3.7',
    workloads: [
      {
        id: workloadId,
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
}

function runCase(tmpDir, name, payload, expectedExit, expectedDecision) {
  const evidencePath = path.join(tmpDir, `${name}.evidence.json`)
  const outPath = path.join(tmpDir, `${name}.evaluation.json`)
  writeJson(evidencePath, payload)
  const result = childProcess.spawnSync(process.execPath, [evaluator, '--evidence', evidencePath, '--json-out', outPath], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  if (result.status !== expectedExit) {
    fail(`${name}: expected exit ${expectedExit}, got ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
  if (!fs.existsSync(outPath)) fail(`${name}: evaluator did not write summary`)
  const summary = JSON.parse(fs.readFileSync(outPath, 'utf8'))
  if (summary.decision !== expectedDecision) {
    fail(`${name}: expected decision ${expectedDecision}, got ${summary.decision}`)
  }
  if (expectedDecision === 'pass' && !String(result.stdout).includes('FULL1_PERF_PARITY:PASS')) {
    fail(`${name}: pass case did not emit FULL1_PERF_PARITY:PASS`)
  }
  if (expectedDecision !== 'pass' && String(result.stdout).includes('FULL1_PERF_PARITY:PASS')) {
    fail(`${name}: failing case emitted FULL1_PERF_PARITY:PASS`)
  }
  return summary
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-perf-evaluator-fixtures-'))
  const passSummary = runCase(
    tmpDir,
    'pass',
    evidence('synthetic-pass', [100, 101, 99, 100, 100], [90, 91, 89, 90, 90]),
    0,
    'pass'
  )
  if (passSummary.marker !== 'FULL1_PERF_PARITY:PASS') fail('pass summary marker mismatch')

  const thresholdSummary = runCase(
    tmpDir,
    'threshold-fail',
    evidence('synthetic-threshold-fail', [100, 101, 99, 100, 100], [120, 121, 119, 120, 120]),
    1,
    'fail'
  )
  if (!JSON.stringify(thresholdSummary.failures).includes('hard ceiling')) {
    fail('threshold fail summary did not record hard ceiling failure')
  }

  const noisySummary = runCase(
    tmpDir,
    'noise-fail',
    evidence('synthetic-noise-fail', [100, 100, 100, 100, 100], [20, 180, 100, 100, 100]),
    1,
    'fail'
  )
  if (!JSON.stringify(noisySummary.failures).includes('noisy')) {
    fail('noise fail summary did not record noisy sample failure')
  }

  fs.rmSync(tmpDir, { recursive: true, force: true })
  console.log('[ci:guards] OK: Full1 perf evaluator synthetic fixtures pass')
}

main()

