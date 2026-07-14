#!/usr/bin/env node
'use strict'

/**
 * Builds and verifies the candidate-bound Full1 macro/eval receipt.
 *
 * The build command opens the verified macro and native-eval summaries and
 * records their hashes. The verify command is used by Gate Full1 so that its
 * aggregate marker comes from this receipt rather than a reusable-job status.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const COMBINED_SCHEMA = 'full1-macro-eval-summary.v1'
const MACRO_SCHEMA = 'macro-runtime-parity-summary.v4'
const EVAL_SCHEMA = 'full1-eval-native-summary.v2'
const AGGREGATE_MARKER = 'FULL1_MACRO_EVAL_PARITY:PASS'
const MACRO_MARKERS = [
  'MACRO_RUNTIME_PARITY_WEEKLY:PASS',
  'FULL1_MACRO_PARITY:PASS',
]
const EVAL_MARKER = 'FULL1_EVAL_NATIVE:PASS'

function requireValue(condition, message) {
  if (!condition) throw new Error(message)
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function isSha256(value) {
  return typeof value === 'string' && /^[0-9a-f]{64}$/i.test(value)
}

function sameMembers(left, right) {
  return Array.isArray(left)
    && left.length === right.length
    && left.every(value => right.includes(value))
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function validateContext(context) {
  requireValue(/^[0-9a-f]{40}$/i.test(context.candidateSha),
    'candidate SHA must contain 40 hexadecimal characters')
  requireValue(/^[1-9][0-9]*$/.test(context.runId), 'run ID must be a positive integer')
  requireValue(/^[1-9][0-9]*$/.test(context.runAttempt), 'run attempt must be a positive integer')
}

function validateMacroSummary(summary, context) {
  requireValue(summary.schema === MACRO_SCHEMA, `expected macro schema ${MACRO_SCHEMA}`)
  requireValue(summary.synthetic === false, 'macro summary must be authentic, not synthetic')
  requireValue(summary.candidate_sha === context.candidateSha, 'macro candidate SHA mismatch')
  requireValue(String(summary.run_id) === context.runId, 'macro run ID mismatch')
  requireValue(String(summary.run_attempt) === context.runAttempt, 'macro run attempt mismatch')
  requireValue(Array.isArray(summary.errors) && summary.errors.length === 0,
    'macro summary contains validation errors')
  requireValue(summary.jobs?.macro_runtime_parity?.result === 'success'
    && summary.jobs?.project_macro_module?.result === 'success',
  'macro summary child jobs did not both succeed')
  requireValue(Array.isArray(summary.proofs)
    && summary.proofs.length === 3
    && summary.proofs.every(proof => proof.verified === true),
  'macro summary does not contain three verified proofs')
  for (const [id, digestFields] of [
    ['inproc', ['timing_summary_sha256', 'markers_sha256']],
    ['external-host', ['timing_summary_sha256', 'markers_sha256']],
    ['project-macro-module', [
      'summary_sha256',
      'receipt_sha256',
      'markers_sha256',
      'native_artifact_sha256',
      'bytecode_artifact_sha256',
    ]],
  ]) {
    const proof = summary.proofs.find(item => item.id === id)
    requireValue(proof, `macro summary is missing proof ${id}`)
    requireValue(digestFields.every(field => isSha256(proof[field])),
      `macro proof ${id} contains an invalid digest`)
    if (id === 'external-host') {
      requireValue(isSha256(proof.host?.receipt_sha256)
        && isSha256(proof.host?.executable_sha256),
      'external-host macro proof contains invalid host digests')
    }
  }
  requireValue(sameMembers(summary.emitted_markers, MACRO_MARKERS),
    'macro summary did not emit both required markers')
}

function validateEvalSummary(summary, context) {
  requireValue(summary.schema === EVAL_SCHEMA, `expected eval schema ${EVAL_SCHEMA}`)
  requireValue(summary.synthetic === false, 'eval summary must be authentic, not synthetic')
  requireValue(summary.candidate_sha === context.candidateSha, 'eval candidate SHA mismatch')
  requireValue(String(summary.run_id) === context.runId, 'eval run ID mismatch')
  requireValue(String(summary.run_attempt) === context.runAttempt, 'eval run attempt mismatch')
  requireValue(summary.oracle?.haxe_version === '4.3.7'
    && /^[0-9a-f]{40}$/i.test(String(summary.oracle?.checkout_commit || '')),
  'eval oracle must identify the Haxe 4.3.7 checkout')
  requireValue(summary.eval_context?.stage0_forbidden === true,
    'eval summary did not forbid stage0')
  requireValue(summary.result?.exit_code === 0 && !summary.result?.signal,
    'eval workload did not exit cleanly')
  requireValue(summary.marker === EVAL_MARKER, `eval summary is missing ${EVAL_MARKER}`)
}

/** Build one combined receipt from the two authenticated lower-level summaries. */
function evaluate(context) {
  const errors = []
  const proofs = []
  try {
    validateContext(context)
  } catch (error) {
    errors.push(error.message)
  }
  if (context.macroResult !== 'success') errors.push(`macro workflow result is ${context.macroResult}`)
  if (context.evalResult !== 'success') errors.push(`eval workflow result is ${context.evalResult}`)

  try {
    const macro = readJson(context.macroSummary)
    validateMacroSummary(macro, context)
    proofs.push({
      id: 'macro',
      summary_schema: macro.schema,
      summary_sha256: sha256File(context.macroSummary),
      markers: MACRO_MARKERS,
      verified: true,
    })
  } catch (error) {
    errors.push(`macro summary: ${error.message}`)
  }

  try {
    const evalSummary = readJson(context.evalSummary)
    validateEvalSummary(evalSummary, context)
    proofs.push({
      id: 'eval',
      summary_schema: evalSummary.schema,
      summary_sha256: sha256File(context.evalSummary),
      markers: [EVAL_MARKER],
      verified: true,
    })
  } catch (error) {
    errors.push(`eval summary: ${error.message}`)
  }

  const passed = errors.length === 0 && proofs.length === 2
  return {
    schema: COMBINED_SCHEMA,
    synthetic: false,
    workflow: 'Full1 / Macro Eval Evidence',
    candidate_sha: context.candidateSha,
    run_id: context.runId,
    run_attempt: context.runAttempt,
    jobs: {
      macro: { result: context.macroResult },
      eval: { result: context.evalResult },
    },
    required_markers: [...MACRO_MARKERS, EVAL_MARKER],
    proofs,
    errors,
    expected_markers: [AGGREGATE_MARKER],
    emitted_markers: passed ? [AGGREGATE_MARKER] : [],
  }
}

/** Validate a previously built combined receipt at its next trust boundary. */
function validateCombinedSummary(summary, context) {
  validateContext(context)
  requireValue(summary.schema === COMBINED_SCHEMA, `expected combined schema ${COMBINED_SCHEMA}`)
  requireValue(summary.synthetic === false, 'combined summary must be authentic, not synthetic')
  requireValue(summary.candidate_sha === context.candidateSha, 'combined candidate SHA mismatch')
  requireValue(String(summary.run_id) === context.runId, 'combined run ID mismatch')
  requireValue(String(summary.run_attempt) === context.runAttempt, 'combined run attempt mismatch')
  requireValue(Array.isArray(summary.errors) && summary.errors.length === 0,
    'combined summary contains validation errors')
  requireValue(sameMembers(summary.required_markers, [...MACRO_MARKERS, EVAL_MARKER]),
    'combined summary required marker set mismatch')
  requireValue(sameMembers(summary.emitted_markers, [AGGREGATE_MARKER]),
    `combined summary is missing ${AGGREGATE_MARKER}`)
  requireValue(Array.isArray(summary.proofs) && summary.proofs.length === 2,
    'combined summary must contain two proof records')
  for (const [id, schema, markers] of [
    ['macro', MACRO_SCHEMA, MACRO_MARKERS],
    ['eval', EVAL_SCHEMA, [EVAL_MARKER]],
  ]) {
    const proof = summary.proofs.find(item => item.id === id)
    requireValue(proof?.verified === true, `combined ${id} proof is not verified`)
    requireValue(proof.summary_schema === schema, `combined ${id} proof schema mismatch`)
    requireValue(isSha256(proof.summary_sha256), `combined ${id} proof digest is invalid`)
    requireValue(sameMembers(proof.markers, markers), `combined ${id} proof marker set mismatch`)
  }
}

function parseFlags(argv) {
  const args = {}
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index]
    if (!flag.startsWith('--')) throw new Error(`unexpected argument: ${flag}`)
    const value = argv[index + 1]
    if (!value || value.startsWith('--')) throw new Error(`missing value for ${flag}`)
    args[flag.slice(2)] = value
    index += 1
  }
  return args
}

function commonContext(args) {
  for (const name of ['candidate-sha', 'run-id', 'run-attempt']) {
    if (!args[name]) throw new Error(`missing --${name}`)
  }
  return {
    candidateSha: args['candidate-sha'],
    runId: String(args['run-id']),
    runAttempt: String(args['run-attempt']),
  }
}

function buildCommand(args) {
  for (const name of ['macro-summary', 'eval-summary', 'output', 'macro-result', 'eval-result']) {
    if (!args[name]) throw new Error(`missing --${name}`)
  }
  const context = {
    ...commonContext(args),
    macroSummary: path.resolve(args['macro-summary']),
    evalSummary: path.resolve(args['eval-summary']),
    output: path.resolve(args.output),
    macroResult: args['macro-result'],
    evalResult: args['eval-result'],
  }
  const summary = evaluate(context)
  fs.mkdirSync(path.dirname(context.output), { recursive: true })
  fs.writeFileSync(context.output, `${JSON.stringify(summary, null, 2)}\n`)
  if (summary.errors.length > 0) {
    for (const error of summary.errors) console.error(`Full1 macro/eval evidence: ${error}`)
    process.exit(1)
  }
  console.log(AGGREGATE_MARKER)
}

function verifyCommand(args) {
  if (!args.summary) throw new Error('missing --summary')
  const context = commonContext(args)
  validateCombinedSummary(readJson(path.resolve(args.summary)), context)
  console.log(AGGREGATE_MARKER)
}

function main() {
  try {
    const command = process.argv[2]
    const args = parseFlags(process.argv.slice(3))
    if (command === 'build') buildCommand(args)
    else if (command === 'verify') verifyCommand(args)
    else throw new Error('expected command: build or verify')
  } catch (error) {
    console.error(`Full1 macro/eval evidence: ${error.message}`)
    process.exit(1)
  }
}

if (require.main === module) main()

module.exports = {
  AGGREGATE_MARKER,
  COMBINED_SCHEMA,
  EVAL_MARKER,
  EVAL_SCHEMA,
  MACRO_MARKERS,
  MACRO_SCHEMA,
  evaluate,
  validateCombinedSummary,
  validateEvalSummary,
  validateMacroSummary,
}
