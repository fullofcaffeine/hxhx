#!/usr/bin/env node
'use strict'

/** Network-free positive and fail-closed fixtures for combined macro/eval evidence. */

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const {
  AGGREGATE_MARKER,
  COMBINED_SCHEMA,
  EVAL_MARKER,
  EVAL_SCHEMA,
  MACRO_MARKERS,
  MACRO_SCHEMA,
  evaluate,
  validateCombinedSummary,
} = require('./full1-macro-eval-evidence.js')

const context = {
  candidateSha: '1234567890abcdef1234567890abcdef12345678',
  runId: '424242',
  runAttempt: '2',
  macroResult: 'success',
  evalResult: 'success',
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function macroProof(id) {
  if (id === 'project-macro-module') {
    return {
      id,
      summary_sha256: '1'.repeat(64),
      receipt_sha256: '2'.repeat(64),
      markers_sha256: '3'.repeat(64),
      native_artifact_sha256: '4'.repeat(64),
      bytecode_artifact_sha256: '5'.repeat(64),
      verified: true,
    }
  }
  return {
    id,
    timing_summary_sha256: '6'.repeat(64),
    markers_sha256: '7'.repeat(64),
    host: id === 'external-host'
      ? { receipt_sha256: '8'.repeat(64), executable_sha256: '9'.repeat(64) }
      : null,
    verified: true,
  }
}

function summaries() {
  return {
    macro: {
      schema: MACRO_SCHEMA,
      synthetic: false,
      candidate_sha: context.candidateSha,
      run_id: context.runId,
      run_attempt: context.runAttempt,
      jobs: {
        macro_runtime_parity: { result: 'success' },
        project_macro_module: { result: 'success' },
      },
      proofs: [
        macroProof('inproc'),
        macroProof('external-host'),
        macroProof('project-macro-module'),
      ],
      errors: [],
      emitted_markers: MACRO_MARKERS,
    },
    eval: {
      schema: EVAL_SCHEMA,
      synthetic: false,
      candidate_sha: context.candidateSha,
      run_id: context.runId,
      run_attempt: context.runAttempt,
      oracle: {
        haxe_version: '4.3.7',
        checkout_commit: 'a'.repeat(40),
      },
      eval_context: { stage0_forbidden: true },
      result: { exit_code: 0, signal: null },
      marker: EVAL_MARKER,
    },
  }
}

function run(mutator = null, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-macro-eval-evidence-'))
  try {
    const fixture = summaries()
    if (mutator) mutator(fixture)
    const macroSummary = path.join(root, 'macro.json')
    const evalSummary = path.join(root, 'eval.json')
    if (!options.removeMacro) {
      fs.writeFileSync(macroSummary,
        options.malformedMacro ? '{bad json\n' : `${JSON.stringify(fixture.macro, null, 2)}\n`)
    }
    if (!options.removeEval) fs.writeFileSync(evalSummary, `${JSON.stringify(fixture.eval, null, 2)}\n`)
    return evaluate({
      ...context,
      macroSummary,
      evalSummary,
      macroResult: options.macroResult || context.macroResult,
      evalResult: options.evalResult || context.evalResult,
    })
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

function assertRejected(summary, fragment) {
  assert.deepStrictEqual(summary.emitted_markers, [])
  assert(summary.errors.some(error => error.includes(fragment)),
    `expected error containing ${fragment}; got ${summary.errors.join('; ')}`)
}

const valid = run()
assert.strictEqual(valid.schema, COMBINED_SCHEMA)
assert.strictEqual(valid.synthetic, false)
assert.strictEqual(valid.candidate_sha, context.candidateSha)
assert.strictEqual(valid.proofs.length, 2)
assert.deepStrictEqual(valid.errors, [])
assert.deepStrictEqual(valid.emitted_markers, [AGGREGATE_MARKER])
validateCombinedSummary(valid, context)

assertRejected(run(null, { removeMacro: true }), 'macro summary')
assertRejected(run(null, { removeEval: true }), 'eval summary')
assertRejected(run(null, { malformedMacro: true }), 'JSON')
assertRejected(run(fixture => { fixture.macro.candidate_sha = 'f'.repeat(40) }),
  'candidate SHA mismatch')
assertRejected(run(fixture => { fixture.eval.run_attempt = '9' }), 'run attempt mismatch')
assertRejected(run(fixture => { fixture.macro.synthetic = true }), 'authentic, not synthetic')
assertRejected(run(fixture => { fixture.eval.synthetic = true }), 'authentic, not synthetic')
assertRejected(run(fixture => { fixture.macro.emitted_markers = [] }), 'both required markers')
assertRejected(run(fixture => { fixture.eval.marker = 'FULL1_EVAL_NATIVE:FAIL' }), 'is missing')
assertRejected(run(fixture => { fixture.eval.eval_context.stage0_forbidden = false }), 'did not forbid stage0')
assertRejected(run(fixture => { fixture.eval.result.exit_code = 1 }), 'did not exit cleanly')
assertRejected(run(fixture => {
  fixture.macro.proofs.find(proof => proof.id === 'inproc').timing_summary_sha256 = 'bad'
}), 'invalid digest')
assertRejected(run(null, { macroResult: 'cancelled' }), 'macro workflow result is cancelled')
assertRejected(run(null, { evalResult: 'failure' }), 'eval workflow result is failure')

const tamperedCombined = clone(valid)
tamperedCombined.proofs[0].summary_sha256 = 'bad'
assert.throws(() => validateCombinedSummary(tamperedCombined, context), /digest is invalid/)
const crossCandidateCombined = clone(valid)
crossCandidateCombined.candidate_sha = 'f'.repeat(40)
assert.throws(() => validateCombinedSummary(crossCandidateCombined, context), /candidate SHA mismatch/)
const syntheticCombined = clone(valid)
syntheticCombined.synthetic = true
assert.throws(() => validateCombinedSummary(syntheticCombined, context), /authentic, not synthetic/)

console.log('FULL1_MACRO_EVAL_EVIDENCE_FIXTURES:PASS')
