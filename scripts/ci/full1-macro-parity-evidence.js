#!/usr/bin/env node
'use strict'

/**
 * Builds the Full1 macro summary from the uploaded mode and project receipts.
 *
 * GitHub job results remain fail-safe control signals, but they cannot create
 * a pass marker. This evaluator opens every required proof artifact, checks
 * its candidate/run identity and behavior markers, and hashes the files that
 * support the aggregate claim.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const AGGREGATE_SCHEMA = 'macro-runtime-parity-summary.v4'
const AGGREGATE_MARKERS = [
  'MACRO_RUNTIME_PARITY_WEEKLY:PASS',
  'FULL1_MACRO_PARITY:PASS',
]
const TIMING_SCHEMA = 'full1-phase-timing-summary.v2'
const PROJECT_SCHEMA = 'hxhx.native-macro-module.v1'
const HOST_SCHEMA = 'macro-runtime-host-evidence.v1'

const MODE_PROOFS = [
  {
    id: 'inproc',
    artifactPrefix: 'macro-runtime-parity-inproc',
    timingName: 'inproc.timings.summary.json',
    requiredPhases: [
      'unit_macro_stage3_no_emit',
      'runci_macro_stage3_no_emit',
      'display_macro_protocol',
    ],
    requiredMarkers: [
      'MACRO_RUNTIME_PARITY_UNIT_INPROC:PASS',
      'MACRO_RUNTIME_PARITY_RUNCI_INPROC:PASS',
      'MACRO_RUNTIME_PARITY_DISPLAY_PROTOCOL_INPROC:PASS',
      'MACRO_RUNTIME_PARITY_INPROC:PASS',
    ],
  },
  {
    id: 'external-host',
    artifactPrefix: 'macro-runtime-parity-external-host',
    timingName: 'external-host.timings.summary.json',
    requiredPhases: [
      'prepare_external_macro_host',
      'unit_macro_stage3_no_emit',
      'runci_macro_stage3_no_emit',
      'display_macro_protocol',
    ],
    requiredMarkers: [
      'MACRO_RUNTIME_EXTERNAL_HOST_ARTIFACT:PASS',
      'MACRO_RUNTIME_PARITY_UNIT_EXTERNAL_HOST:PASS',
      'MACRO_RUNTIME_PARITY_RUNCI_EXTERNAL_HOST:PASS',
      'MACRO_RUNTIME_PARITY_DISPLAY_PROTOCOL_EXTERNAL_HOST:PASS',
      'MACRO_RUNTIME_PARITY_EXTERNAL_HOST:PASS',
    ],
  },
]

const PROJECT_PROOF = {
  id: 'project-macro-module',
  artifactPrefix: 'project-macro-module',
  requiredMarkers: [
    'PROJECT_MACRO_MODULE_ORACLE:PASS',
    'PROJECT_MACRO_MODULE_BUILD:PASS',
    'PROJECT_MACRO_MODULE_INPROC:PASS',
    'PROJECT_MACRO_MODULE_EXTERNAL_HOST:PASS',
    'PROJECT_MACRO_MODULE_NEGATIVE_PATHS:PASS',
    'PROJECT_MACRO_MODULE:PASS',
  ],
}

function requireValue(condition, message) {
  if (!condition) throw new Error(message)
}

function sha256File(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function isSha256(value) {
  return typeof value === 'string' && /^[0-9a-f]{64}$/i.test(value)
}

function artifactName(spec, context) {
  return `${spec.artifactPrefix}-${context.runId}-${context.runAttempt}`
}

function findFiles(directory, fileName) {
  const matches = []
  if (!fs.existsSync(directory)) return matches
  const visit = current => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const resolved = path.join(current, entry.name)
      if (entry.isDirectory()) visit(resolved)
      else if (entry.name === fileName) matches.push(resolved)
    }
  }
  visit(directory)
  return matches
}

function findOne(directory, fileName) {
  const matches = findFiles(directory, fileName)
  requireValue(matches.length === 1,
    `${path.basename(directory)} must contain exactly one ${fileName}; found ${matches.length}`)
  return matches[0]
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function readLines(filePath) {
  requireValue(fs.existsSync(filePath), `missing ${path.basename(filePath)}`)
  return fs.readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(Boolean)
}

function readKeyValues(filePath) {
  const values = {}
  for (const line of readLines(filePath)) {
    const separator = line.indexOf('=')
    requireValue(separator > 0, `${path.basename(filePath)} contains an invalid line`)
    const key = line.slice(0, separator)
    requireValue(!(key in values), `${path.basename(filePath)} repeats ${key}`)
    values[key] = line.slice(separator + 1)
  }
  return values
}

function requireMarkers(filePath, requiredMarkers) {
  const markers = new Set(readLines(filePath))
  for (const marker of requiredMarkers) {
    requireValue(markers.has(marker), `${path.basename(filePath)} is missing ${marker}`)
  }
}

function validateTimingSummary(summary, spec, context) {
  requireValue(summary.schema === TIMING_SCHEMA, `expected timing schema ${TIMING_SCHEMA}`)
  requireValue(summary.marker === 'FULL1_PHASE_TIMING_REPORT:PASS', 'timing summary did not pass')
  requireValue(summary.git?.commit === context.candidateSha, 'timing candidate SHA mismatch')
  requireValue(summary.git?.tracked_source_clean_at_summary === true,
    'timing summary was not produced from a clean tracked tree')
  requireValue(String(summary.ci?.run_id) === context.runId, 'timing run ID mismatch')
  requireValue(String(summary.ci?.run_attempt) === context.runAttempt, 'timing run attempt mismatch')
  requireValue(summary.ci?.workflow_sha === context.candidateSha, 'timing workflow SHA mismatch')
  requireValue(summary.workflow === 'macro-runtime-parity-weekly', 'unexpected timing workflow')
  requireValue(summary.job === spec.id, `expected timing job ${spec.id}`)
  requireValue(summary.failed_phase_count === 0, `${spec.id} timing summary contains a failed phase`)
  requireValue(Array.isArray(summary.phases), `${spec.id} timing phases are missing`)
  for (const phaseName of spec.requiredPhases) {
    const phase = summary.phases.find(item => item.phase === phaseName)
    requireValue(phase, `${spec.id} timing summary is missing phase ${phaseName}`)
    requireValue(phase.status === 'pass' && phase.exit_code === 0,
      `${spec.id} phase ${phaseName} did not pass`)
    requireValue(phase.git_commit === context.candidateSha, `${spec.id} phase candidate mismatch`)
    requireValue(String(phase.run_id) === context.runId, `${spec.id} phase run ID mismatch`)
    requireValue(String(phase.run_attempt) === context.runAttempt,
      `${spec.id} phase run attempt mismatch`)
  }
}

function verifyRelativeArtifact(summaryPath, relativePath, expectedDigest) {
  requireValue(typeof relativePath === 'string' && relativePath.length > 0,
    'project macro artifact path is missing')
  requireValue(!path.isAbsolute(relativePath), 'project macro artifact path must be relative')
  const directory = path.dirname(summaryPath)
  const resolved = path.resolve(directory, relativePath)
  const relativeResolved = path.relative(directory, resolved)
  requireValue(relativeResolved !== '..'
    && !relativeResolved.startsWith(`..${path.sep}`)
    && !path.isAbsolute(relativeResolved),
  'project macro artifact must stay beside its receipt')
  requireValue(fs.existsSync(resolved) && fs.statSync(resolved).isFile(),
    `missing project macro artifact ${relativePath}`)
  requireValue(isSha256(expectedDigest), 'project macro artifact SHA-256 is missing or invalid')
  const actual = sha256File(resolved)
  requireValue(actual === expectedDigest, `project macro artifact digest mismatch for ${relativePath}`)
  return actual
}

function validateExternalHost(directory, context) {
  const receiptPath = findOne(directory, 'macro-runtime-host-receipt.json')
  const receipt = readJson(receiptPath)
  requireValue(receipt.schema === HOST_SCHEMA, `expected macro host schema ${HOST_SCHEMA}`)
  requireValue(receipt.marker === 'MACRO_RUNTIME_EXTERNAL_HOST_ARTIFACT:PASS',
    'external host receipt did not pass')
  requireValue(receipt.source?.commit === context.candidateSha, 'external host candidate SHA mismatch')
  requireValue(receipt.source?.trackedSourceClean === true,
    'external host receipt was not produced from a clean tracked tree')
  requireValue(receipt.build?.stage0Forbidden === true, 'external host did not forbid stage0')
  requireValue(receipt.protocol?.version === 1
    && receipt.protocol?.handshake === 'ok', 'external host protocol handshake did not pass')
  requireValue(isSha256(receipt.artifact?.sha256), 'external host SHA-256 is missing or invalid')
  const executablePath = path.join(directory, 'candidate-host', 'hxhx-macro-host.exe')
  requireValue(fs.existsSync(executablePath), 'external host executable is missing')
  const actualDigest = sha256File(executablePath)
  requireValue(actualDigest === receipt.artifact.sha256,
    'external host executable digest does not match its receipt')
  return {
    receipt_sha256: sha256File(receiptPath),
    executable_sha256: actualDigest,
  }
}

function validateModeProof(spec, context) {
  const name = artifactName(spec, context)
  const directory = path.join(context.artifactsDir, name)
  requireValue(fs.existsSync(directory) && fs.statSync(directory).isDirectory(),
    `missing artifact directory ${name}`)
  const timingPath = findOne(directory, spec.timingName)
  const timing = readJson(timingPath)
  validateTimingSummary(timing, spec, context)
  const markersPath = findOne(directory, 'markers.txt')
  requireMarkers(markersPath, spec.requiredMarkers)
  const metaPath = findOne(directory, 'meta.txt')
  const meta = readKeyValues(metaPath)
  requireValue(meta.macro_runtime_mode === spec.id, `expected macro mode ${spec.id}`)
  const host = spec.id === 'external-host' ? validateExternalHost(directory, context) : null
  return {
    id: spec.id,
    artifact_name: name,
    timing_summary_path: path.relative(directory, timingPath),
    timing_summary_sha256: sha256File(timingPath),
    markers_sha256: sha256File(markersPath),
    required_markers: spec.requiredMarkers,
    host,
    verified: true,
  }
}

function validateProjectProof(context) {
  const spec = PROJECT_PROOF
  const name = artifactName(spec, context)
  const directory = path.join(context.artifactsDir, name)
  requireValue(fs.existsSync(directory) && fs.statSync(directory).isDirectory(),
    `missing artifact directory ${name}`)
  const summaryPath = findOne(directory, 'receipt-summary.json')
  const receiptPath = findOne(directory, 'project-macro-receipt.json')
  const markersPath = findOne(directory, 'markers.txt')
  const metaPath = findOne(directory, 'meta.txt')
  const summary = readJson(summaryPath)
  const receipt = readJson(receiptPath)
  const meta = readKeyValues(metaPath)
  requireMarkers(markersPath, spec.requiredMarkers)

  for (const [owner, value] of [['project summary', summary], ['project receipt', receipt]]) {
    requireValue(value.schema === PROJECT_SCHEMA, `${owner} expected schema ${PROJECT_SCHEMA}`)
    requireValue(value.candidateCommit === context.candidateSha, `${owner} candidate SHA mismatch`)
    requireValue(value.pluginId === 'hxhx.project-macro.fixture', `${owner} plugin ID mismatch`)
    requireValue(Array.isArray(value.expressions)
      && value.expressions.includes('projectmacro.ProjectMacro.message()'),
    `${owner} expression registration is missing`)
  }
  requireValue(meta.candidate_commit === context.candidateSha, 'project macro metadata candidate mismatch')
  requireValue(meta.plugin_id === 'hxhx.project-macro.fixture', 'project macro metadata plugin mismatch')
  requireValue(receipt.abiVersion === 1 && receipt.macroApiVersion === 1,
    'project macro ABI/API version mismatch')

  const nativeDigest = verifyRelativeArtifact(
    receiptPath,
    receipt.artifacts?.native?.path,
    receipt.artifacts?.native?.sha256,
  )
  const bytecodeDigest = verifyRelativeArtifact(
    receiptPath,
    receipt.artifacts?.bytecode?.path,
    receipt.artifacts?.bytecode?.sha256,
  )
  requireValue(summary.artifacts?.native?.sha256 === nativeDigest,
    'project summary native digest does not match its receipt')
  requireValue(summary.artifacts?.bytecode?.sha256 === bytecodeDigest,
    'project summary bytecode digest does not match its receipt')

  return {
    id: spec.id,
    artifact_name: name,
    summary_sha256: sha256File(summaryPath),
    receipt_sha256: sha256File(receiptPath),
    markers_sha256: sha256File(markersPath),
    native_artifact_sha256: nativeDigest,
    bytecode_artifact_sha256: bytecodeDigest,
    required_markers: spec.requiredMarkers,
    verified: true,
  }
}

/** Validate all leaf artifacts and build the only summary allowed to emit macro parity. */
function evaluate(context) {
  const errors = []
  const proofs = []
  if (!/^[0-9a-f]{40}$/i.test(context.candidateSha)) {
    errors.push('candidate SHA must contain 40 hexadecimal characters')
  }
  if (context.matrixResult !== 'success') errors.push(`macro matrix result is ${context.matrixResult}`)
  if (context.projectResult !== 'success') errors.push(`project macro result is ${context.projectResult}`)

  for (const spec of MODE_PROOFS) {
    try {
      proofs.push(validateModeProof(spec, context))
    } catch (error) {
      errors.push(`${artifactName(spec, context)}: ${error.message}`)
    }
  }
  try {
    proofs.push(validateProjectProof(context))
  } catch (error) {
    errors.push(`${artifactName(PROJECT_PROOF, context)}: ${error.message}`)
  }

  const passed = errors.length === 0 && proofs.length === MODE_PROOFS.length + 1
  return {
    schema: AGGREGATE_SCHEMA,
    synthetic: false,
    workflow: 'Macro Runtime Parity (Weekly)',
    candidate_sha: context.candidateSha,
    run_id: context.runId,
    run_attempt: context.runAttempt,
    jobs: {
      macro_runtime_parity: { result: context.matrixResult },
      project_macro_module: { result: context.projectResult },
    },
    required_markers: [
      ...MODE_PROOFS.flatMap(spec => spec.requiredMarkers),
      ...PROJECT_PROOF.requiredMarkers,
    ],
    proofs,
    errors,
    expected_markers: AGGREGATE_MARKERS,
    emitted_markers: passed ? AGGREGATE_MARKERS : [],
  }
}

function parseArgs(argv) {
  const args = {}
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index]
    if (!flag.startsWith('--')) throw new Error(`unexpected argument: ${flag}`)
    const value = argv[index + 1]
    if (!value || value.startsWith('--')) throw new Error(`missing value for ${flag}`)
    args[flag.slice(2)] = value
    index += 1
  }
  for (const name of [
    'artifacts-dir',
    'output',
    'candidate-sha',
    'run-id',
    'run-attempt',
    'matrix-result',
    'project-result',
  ]) {
    if (!args[name]) throw new Error(`missing --${name}`)
  }
  return {
    artifactsDir: path.resolve(args['artifacts-dir']),
    output: path.resolve(args.output),
    candidateSha: args['candidate-sha'],
    runId: String(args['run-id']),
    runAttempt: String(args['run-attempt']),
    matrixResult: args['matrix-result'],
    projectResult: args['project-result'],
  }
}

function main() {
  try {
    const context = parseArgs(process.argv.slice(2))
    const summary = evaluate(context)
    fs.mkdirSync(path.dirname(context.output), { recursive: true })
    fs.writeFileSync(context.output, `${JSON.stringify(summary, null, 2)}\n`)
    if (summary.errors.length > 0) {
      for (const error of summary.errors) console.error(`Full1 macro evidence: ${error}`)
      process.exit(1)
    }
    for (const marker of AGGREGATE_MARKERS) console.log(marker)
  } catch (error) {
    console.error(`Full1 macro evidence: ${error.message}`)
    process.exit(1)
  }
}

if (require.main === module) main()

module.exports = {
  AGGREGATE_MARKERS,
  AGGREGATE_SCHEMA,
  HOST_SCHEMA,
  MODE_PROOFS,
  PROJECT_PROOF,
  PROJECT_SCHEMA,
  TIMING_SCHEMA,
  artifactName,
  evaluate,
}
