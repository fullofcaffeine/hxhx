#!/usr/bin/env node
'use strict'

/** Network-free positive and fail-closed fixtures for Full1 macro evidence. */

const assert = require('assert')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const {
  AGGREGATE_MARKERS,
  AGGREGATE_SCHEMA,
  HOST_SCHEMA,
  MODE_PROOFS,
  PROJECT_PROOF,
  PROJECT_SCHEMA,
  TIMING_SCHEMA,
  artifactName,
  evaluate,
} = require('./full1-macro-parity-evidence.js')

const context = {
  candidateSha: '1234567890abcdef1234567890abcdef12345678',
  runId: '424242',
  runAttempt: '2',
  matrixResult: 'success',
  projectResult: 'success',
}
const hostBody = Buffer.from('repo-owned macro host fixture\n')
const nativeBody = Buffer.from('repo-owned native project macro fixture\n')
const bytecodeBody = Buffer.from('repo-owned bytecode project macro fixture\n')

function digest(body) {
  return crypto.createHash('sha256').update(body).digest('hex')
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function timing(spec) {
  return {
    schema: TIMING_SCHEMA,
    marker: 'FULL1_PHASE_TIMING_REPORT:PASS',
    git: {
      commit: context.candidateSha,
      tracked_source_clean_at_summary: true,
    },
    ci: {
      run_id: context.runId,
      run_attempt: context.runAttempt,
      workflow_sha: context.candidateSha,
    },
    workflow: 'macro-runtime-parity-weekly',
    job: spec.id,
    failed_phase_count: 0,
    phases: spec.requiredPhases.map(phase => ({
      phase,
      status: 'pass',
      exit_code: 0,
      git_commit: context.candidateSha,
      run_id: context.runId,
      run_attempt: context.runAttempt,
    })),
  }
}

function values() {
  const modes = {}
  for (const spec of MODE_PROOFS) {
    modes[spec.id] = {
      timing: timing(spec),
      markers: spec.requiredMarkers,
      meta: {
        macro_runtime_mode: spec.id,
        marker_suffix: spec.id === 'inproc' ? 'INPROC' : 'EXTERNAL_HOST',
      },
    }
  }
  modes['external-host'].receipt = {
    schema: HOST_SCHEMA,
    marker: 'MACRO_RUNTIME_EXTERNAL_HOST_ARTIFACT:PASS',
    source: {
      commit: context.candidateSha,
      trackedSourceClean: true,
    },
    build: { stage0Forbidden: true },
    artifact: { sha256: digest(hostBody) },
    protocol: { version: 1, handshake: 'ok' },
  }

  const receipt = {
    schema: PROJECT_SCHEMA,
    candidateCommit: context.candidateSha,
    pluginId: 'hxhx.project-macro.fixture',
    abiVersion: 1,
    macroApiVersion: 1,
    expressions: ['projectmacro.ProjectMacro.message()'],
    artifacts: {
      native: { path: 'project-macro.cmxs', sha256: digest(nativeBody) },
      bytecode: { path: 'project-macro.cma', sha256: digest(bytecodeBody) },
    },
  }
  const summary = clone(receipt)
  delete summary.abiVersion
  delete summary.macroApiVersion
  summary.artifacts.native.path = '/diagnostic-only/project-macro.cmxs'
  summary.artifacts.bytecode.path = '/diagnostic-only/project-macro.cma'
  return {
    modes,
    project: {
      receipt,
      summary,
      markers: PROJECT_PROOF.requiredMarkers,
      meta: {
        candidate_commit: context.candidateSha,
        plugin_id: 'hxhx.project-macro.fixture',
        expression: 'projectmacro.ProjectMacro.message()',
      },
    },
  }
}

function writeKeyValues(filePath, entries) {
  fs.writeFileSync(filePath,
    `${Object.entries(entries).map(([key, value]) => `${key}=${value}`).join('\n')}\n`)
}

function writeFixture(root, fixture, options) {
  for (const spec of MODE_PROOFS) {
    if (options.removeId === spec.id) continue
    const directory = path.join(root, artifactName(spec, context))
    fs.mkdirSync(directory, { recursive: true })
    fs.writeFileSync(path.join(directory, spec.timingName),
      options.malformedId === spec.id ? '{bad json\n' : `${JSON.stringify(fixture.modes[spec.id].timing, null, 2)}\n`)
    fs.writeFileSync(path.join(directory, 'markers.txt'), `${fixture.modes[spec.id].markers.join('\n')}\n`)
    writeKeyValues(path.join(directory, 'meta.txt'), fixture.modes[spec.id].meta)
    if (options.duplicateId === spec.id) {
      const duplicate = path.join(directory, 'duplicate')
      fs.mkdirSync(duplicate)
      fs.writeFileSync(path.join(duplicate, spec.timingName),
        `${JSON.stringify(fixture.modes[spec.id].timing, null, 2)}\n`)
    }
    if (spec.id === 'external-host') {
      fs.mkdirSync(path.join(directory, 'candidate-host'))
      fs.writeFileSync(path.join(directory, 'candidate-host', 'hxhx-macro-host.exe'),
        options.tamperHost ? Buffer.from('changed\n') : hostBody)
      fs.writeFileSync(path.join(directory, 'macro-runtime-host-receipt.json'),
        `${JSON.stringify(fixture.modes[spec.id].receipt, null, 2)}\n`)
    }
  }

  if (options.removeId === PROJECT_PROOF.id) return
  const directory = path.join(root, artifactName(PROJECT_PROOF, context))
  const moduleDirectory = path.join(directory, 'module')
  fs.mkdirSync(moduleDirectory, { recursive: true })
  fs.writeFileSync(path.join(directory, 'receipt-summary.json'),
    `${JSON.stringify(fixture.project.summary, null, 2)}\n`)
  fs.writeFileSync(path.join(moduleDirectory, 'project-macro-receipt.json'),
    `${JSON.stringify(fixture.project.receipt, null, 2)}\n`)
  fs.writeFileSync(path.join(moduleDirectory, 'project-macro.cmxs'),
    options.tamperProject ? Buffer.from('changed\n') : nativeBody)
  fs.writeFileSync(path.join(moduleDirectory, 'project-macro.cma'), bytecodeBody)
  fs.writeFileSync(path.join(directory, 'markers.txt'), `${fixture.project.markers.join('\n')}\n`)
  writeKeyValues(path.join(directory, 'meta.txt'), fixture.project.meta)
}

function run(mutator = null, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-macro-evidence-'))
  try {
    const fixture = values()
    if (mutator) mutator(fixture)
    writeFixture(root, fixture, options)
    return evaluate({
      ...context,
      artifactsDir: root,
      matrixResult: options.matrixResult || context.matrixResult,
      projectResult: options.projectResult || context.projectResult,
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
assert.strictEqual(valid.schema, AGGREGATE_SCHEMA)
assert.strictEqual(valid.synthetic, false)
assert.strictEqual(valid.candidate_sha, context.candidateSha)
assert.strictEqual(valid.proofs.length, 3)
assert.deepStrictEqual(valid.errors, [])
assert.deepStrictEqual(valid.emitted_markers, AGGREGATE_MARKERS)

assertRejected(run(null, { removeId: 'inproc' }), 'missing artifact directory')
assertRejected(run(null, { removeId: PROJECT_PROOF.id }), 'missing artifact directory')
assertRejected(run(null, { duplicateId: 'external-host' }), 'exactly one')
assertRejected(run(null, { malformedId: 'inproc' }), 'JSON')
assertRejected(run(fixture => {
  fixture.modes.inproc.timing.git.commit = 'f'.repeat(40)
}), 'candidate SHA mismatch')
assertRejected(run(fixture => {
  fixture.modes.inproc.timing.ci.run_attempt = '9'
}), 'run attempt mismatch')
assertRejected(run(fixture => {
  fixture.modes.inproc.markers = fixture.modes.inproc.markers.slice(1)
}), 'is missing')
assertRejected(run(fixture => {
  fixture.modes.inproc.timing.phases[0].status = 'fail'
}), 'did not pass')
assertRejected(run(fixture => {
  fixture.modes['external-host'].receipt.build.stage0Forbidden = false
}), 'did not forbid stage0')
assertRejected(run(null, { tamperHost: true }), 'digest does not match')
assertRejected(run(null, { tamperProject: true }), 'digest mismatch')
assertRejected(run(null, { matrixResult: 'failure' }), 'matrix result is failure')
assertRejected(run(null, { projectResult: 'cancelled' }), 'project macro result is cancelled')

console.log('FULL1_MACRO_PARITY_EVIDENCE_FIXTURES:PASS')
