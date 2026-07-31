#!/usr/bin/env node
/** Verify compiler-scale report hashing, equivalence, and performance gates. */

'use strict'

const assert = require('assert')
const { spawnSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '../..')
const helper = path.join(root, 'scripts/ci/compiler-scale-reflaxe-server-evidence.js')
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-compiler-scale-server-fixture-'))

function run(args, expectedStatus = 0) {
  const result = spawnSync(process.execPath, [helper, ...args], { encoding: 'utf8' })
  assert.strictEqual(result.status, expectedStatus, result.stderr || result.stdout)
  return result
}

function write(file, value, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, value)
  if (mode) fs.chmodSync(file, mode)
}

function makeCapture(label, content = 'same generated source\n') {
  const out = path.join(temp, label, 'out')
  const executable = path.join(temp, label, 'out.exe')
  const stdout = path.join(temp, label, 'version.stdout')
  const stderr = path.join(temp, label, 'version.stderr')
  const capture = path.join(temp, `${label}.capture.json`)
  write(path.join(out, 'Main.ml'), content)
  write(path.join(out, '_GeneratedFiles.json'), JSON.stringify({ filesGenerated: ['Main.ml'] }))
  write(path.join(out, 'ocaml_artifact_manifest.json'), JSON.stringify({
    programRevision: `sha256:${'1'.repeat(64)}`,
    summary: { sourceBundleRevision: `sha256:${'2'.repeat(64)}` }
  }))
  write(executable, 'same native binary\n', 0o755)
  write(stdout, 'hxhx 0.1.0\n')
  write(stderr, '')
  run([
    'capture',
    '--output-dir', out,
    '--executable', executable,
    '--version-stdout', stdout,
    '--version-stderr', stderr,
    '--version-exit', '0',
    '--out', capture
  ])
  return capture
}

function makeTargetPhase(label, outcome, sequence, targetLifecycleMilliseconds, overflowTopHeap = false) {
  const file = path.join(temp, `${label}.target-phase.json`)
  const exactHit = outcome === 'exact-hit'
  write(file, JSON.stringify({
    schemaVersion: 2,
    model: 'reflaxe-ocaml-target-reuse-phase',
    outcome,
    finalProgram: {
      revision: `sha256:${'3'.repeat(64)}`,
      programMembershipRevision: `sha256:${'4'.repeat(64)}`,
      hostRequestRevision: `sha256:${'5'.repeat(64)}`,
      compatibilityProgramRevision: `sha256:${'1'.repeat(64)}`,
      declarationCount: 100
    },
    targetRequest: {
      namespace: 'reflaxe.ocaml:exact-target-source-bundle:v1',
      revision: `sha256:${'6'.repeat(64)}`,
      eligible: true,
      blockers: []
    },
    timing: {
      targetRevisionObservationMilliseconds: 5,
      finalProgramFingerprintAndKeyMilliseconds: 10,
      targetLifecycleMilliseconds,
      missPreparationMilliseconds: exactHit ? 0 : 200000,
      lookupMilliseconds: 1,
      payloadValidationMilliseconds: exactHit ? 2 : 0,
      replayFilesMilliseconds: exactHit ? 5000 : 0,
      replayReceiptAndManifestMilliseconds: exactHit ? 1000 : 0,
      outputPublicationMilliseconds: 100
    },
    work: {
      semanticCompilerRan: !exactHit,
      missPreparationRan: !exactHit,
      lookupRan: true,
      replaySucceeded: exactHit,
      payloadBytes: 1000
    },
    macroRealm: {
      identityRevision: `sha256:${'7'.repeat(64)}`,
      requestSequence: sequence,
      survivedPriorRequest: sequence > 1,
      resetGeneration: 0,
      resetCause: 'process-start'
    },
    catalog: {
      totalBudgetBytes: 134217728,
      maximumEntryBytes: 67108864,
      entryCount: 1,
      payloadBytes: 1000,
      estimatedOverheadBytes: 128,
      activeLeases: 0,
      hits: exactHit ? 1 : 0,
      misses: [{ reason: 'not-found', count: 1 }],
      ineligibleRequests: 0,
      admissions: 1,
      rejectedAdmissions: 0,
      evictions: 0,
      quarantines: 0
    },
    gc: {
      status: overflowTopHeap ? 'partial-overflow' : 'observed',
      heapWords: 10000,
      liveWords: 5000,
      freeWords: 5000,
      topHeapWords: overflowTopHeap ? null : 12000,
      minorCollections: 10,
      majorCollections: 2,
      compactions: 0,
      stackWords: 100,
      overflowedFields: overflowTopHeap ? ['topHeapWords'] : []
    }
  }))
  return file
}

function replaceFlagValue(args, flag, value) {
  const result = args.slice()
  const index = result.indexOf(flag)
  assert(index >= 0, `missing fixture flag ${flag}`)
  result[index + 1] = value
  return result
}

try {
  const cold = makeCapture('cold')
  const warm = makeCapture('warm')
  const coldTargetPhase = makeTargetPhase('cold', 'compiled-miss', 1, 250000)
  const warmTargetPhase = makeTargetPhase('warm', 'exact-hit', 2, 15000)
  const capacity = path.join(temp, 'capacity.json')
  const report = path.join(temp, 'report.json')
  write(capacity, JSON.stringify({ schema: 'fixture.capacity.v1', status: 'pass' }))
  const common = [
    '--cold-capture', cold,
    '--warm-capture', warm,
    '--cold-target-phase', coldTargetPhase,
    '--warm-target-phase', warmTargetPhase,
    '--capacity-report', capacity,
    '--source-commit', 'a'.repeat(40),
    '--source-clean-at-start', 'true',
    '--source-clean-at-end', 'true',
    '--haxe-bin', '/fixture/haxe',
    '--haxe-version', '4.3.7',
    '--ocamlopt-version', '5.3.0',
    '--dune-version', '3.21.0',
    '--generation-ceiling-seconds', '3000',
    '--dune-ceiling-seconds', '1800',
    '--ceiling-rationale', 'fixture measurement',
    '--cold-generation-ms', '300000',
    '--cold-dune-ms', '60000',
    '--warm-generation-ms', '120000',
    '--warm-dune-ms', '1000',
    '--minimum-absolute-saved-ms', '120000',
    '--maximum-warm-to-cold-ratio', '0.8',
    '--maximum-target-lifecycle-ratio', '0.2',
    '--rss-baseline-kb', '100',
    '--rss-after-cold-kb', '200',
    '--rss-after-warm-kb', '250',
    '--rss-peak-kb', '275',
    '--rss-final-kb', '250',
    '--owned-pids-after-stop', '0',
    '--private-candidates-after-stop', '0',
    '--pid-state-after-stop', '0',
    '--out', report
  ]
  run(['report', ...common])
  run(['validate', '--report', report])
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'))
  assert.strictEqual(parsed.status, 'pass')
  assert.strictEqual(parsed.performance.material_benefit, true)
  assert.strictEqual(parsed.performance.target_reuse_mechanism_pass, true)
  assert.strictEqual(parsed.warm.target_phase.outcome, 'exact-hit')
  assert.strictEqual(parsed.cold.capture.generated_tree.revision, parsed.warm.capture.generated_tree.revision)

  const overflowColdPhase = makeTargetPhase('overflow-cold', 'compiled-miss', 1, 250000, true)
  const overflowReport = path.join(temp, 'overflow-report.json')
  let overflowArgs = replaceFlagValue(common, '--cold-target-phase', overflowColdPhase)
  overflowArgs = replaceFlagValue(overflowArgs, '--out', overflowReport)
  run(['report', ...overflowArgs])
  run(['validate', '--report', overflowReport])
  assert.strictEqual(JSON.parse(fs.readFileSync(overflowReport, 'utf8')).cold.target_phase.gc.status, 'partial-overflow')

  const invalidOverflowPhase = makeTargetPhase('invalid-overflow', 'compiled-miss', 1, 250000, true)
  const invalidOverflow = JSON.parse(fs.readFileSync(invalidOverflowPhase, 'utf8'))
  invalidOverflow.gc.overflowedFields = []
  write(invalidOverflowPhase, JSON.stringify(invalidOverflow))
  const invalidOverflowReport = path.join(temp, 'invalid-overflow-report.json')
  let invalidOverflowArgs = replaceFlagValue(common, '--cold-target-phase', invalidOverflowPhase)
  invalidOverflowArgs = replaceFlagValue(invalidOverflowArgs, '--out', invalidOverflowReport)
  run(['report', ...invalidOverflowArgs], 1)

  const mismatchedWarm = makeCapture('mismatch', 'different generated source\n')
  const mismatchReport = path.join(temp, 'mismatch-report.json')
  let mismatchArgs = replaceFlagValue(common, '--warm-capture', mismatchedWarm)
  mismatchArgs = replaceFlagValue(mismatchArgs, '--out', mismatchReport)
  run(['report', ...mismatchArgs], 1)
  assert.strictEqual(JSON.parse(fs.readFileSync(mismatchReport, 'utf8')).status, 'fail')

  const slowReport = path.join(temp, 'slow-report.json')
  let slowArgs = replaceFlagValue(common, '--warm-generation-ms', '290000')
  slowArgs = replaceFlagValue(slowArgs, '--out', slowReport)
  run(['report', ...slowArgs], 1)
  assert.strictEqual(JSON.parse(fs.readFileSync(slowReport, 'utf8')).performance.material_benefit, false)

  const falseHitPhase = makeTargetPhase('false-hit', 'compiled-miss', 2, 15000)
  const falseHitReport = path.join(temp, 'false-hit-report.json')
  let falseHitArgs = replaceFlagValue(common, '--warm-target-phase', falseHitPhase)
  falseHitArgs = replaceFlagValue(falseHitArgs, '--out', falseHitReport)
  run(['report', ...falseHitArgs], 1)
  assert.strictEqual(JSON.parse(fs.readFileSync(falseHitReport, 'utf8')).status, 'fail')

  const slowTargetPhase = makeTargetPhase('slow-target', 'exact-hit', 2, 100000)
  const slowTargetReport = path.join(temp, 'slow-target-report.json')
  let slowTargetArgs = replaceFlagValue(common, '--warm-target-phase', slowTargetPhase)
  slowTargetArgs = replaceFlagValue(slowTargetArgs, '--out', slowTargetReport)
  run(['report', ...slowTargetArgs], 1)
  const slowTargetParsed = JSON.parse(fs.readFileSync(slowTargetReport, 'utf8'))
  assert.strictEqual(slowTargetParsed.performance.target_reuse_mechanism_pass, false)

  console.log('COMPILER_SCALE_REFLAXE_SERVER_EVIDENCE_FIXTURE:PASS')
} finally {
  fs.rmSync(temp, { recursive: true, force: true })
}
