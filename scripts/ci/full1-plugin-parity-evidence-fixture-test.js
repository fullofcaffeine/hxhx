#!/usr/bin/env node
'use strict'

/** Network-free positive and fail-closed fixtures for plugin evidence. */

const assert = require('assert')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const {
  AGGREGATE_MARKER,
  AGGREGATE_SCHEMA,
  PINNED_REFLAXE_ELIXIR,
  PROOF_SCHEMA,
  PROOFS,
  artifactName,
  evaluate,
} = require('./full1-plugin-parity-evidence.js')

const context = {
  candidateSha: '1234567890abcdef1234567890abcdef12345678',
  runId: '424242',
  runAttempt: '2',
  matrixResult: 'success',
}
const evidenceBody = Buffer.from('repo-owned plugin evidence fixture\n')
const digest = crypto.createHash('sha256').update(evidenceBody).digest('hex')
const evidenceArtifact = 'verified-plugin-artifact.bin'

function common(route, marker) {
  return {
    schema: PROOF_SCHEMA,
    synthetic: false,
    route,
    candidateSha: context.candidateSha,
    workflowRun: { id: context.runId, attempt: context.runAttempt },
    marker,
    result: marker,
  }
}

function plugin(pluginId, loadSideEffect) {
  return {
    pluginId,
    targetId: 'js-native',
    artifactKind: 'ocaml-dynlink',
    artifactSha256: digest,
    evidenceArtifact,
    loadSideEffect,
  }
}

function fixtures() {
  return {
    'upstream-to-hxhx': {
      ...common('upstream-to-hxhx', 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS'),
      hostCompiler: { kind: 'upstream-haxe', version: '4.3.7' },
      hxhx: { stage0Forbidden: true },
      plugin: plugin('full1.reflaxe.ocaml.upstream', 'full1_upstream_plugin_loaded=ok'),
      sampleCompile: { providerType: 'backend.js.JsBackend', selectedImpl: 'provider/js-native-wrapper', runtimeStdout: 'sum=6' },
    },
    'hxhx-to-hxhx': {
      ...common('hxhx-to-hxhx', 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS'),
      pluginCompiler: { kind: 'hxhx-stage3', stage0Forbidden: true },
      sourceBuildCompiler: { kind: 'stage0-haxe-for-hxhx-binary-build', version: '4.3.7' },
      hxhx: { stage0Forbidden: true },
      plugin: plugin('full1.reflaxe.ocaml.hxhx', 'full1_hxhx_plugin_loaded=ok'),
      sampleCompile: { providerType: 'backend.js.JsBackend', selectedImpl: 'provider/js-native-wrapper', runtimeStdout: 'sum=6' },
    },
    'upstream-host-adapter': {
      ...common('upstream-host-adapter', 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS'),
      artifactCompiler: { kind: 'upstream-haxe', version: '4.3.7' },
      upstreamHostAdapter: {
        kind: 'haxe-eval',
        loadApi: 'eval.vm.Context.loadPlugin',
        crossHostBinaryCompatibility: false,
        trueCompilerTargetPluginAbi: false,
      },
      source: { commit: PINNED_REFLAXE_ELIXIR },
      pluginArtifact: {
        artifactSha256: digest,
        evidenceArtifact,
        builtArtifacts: ['plugin.cma', 'plugin.cmxs'],
        loadStatus: 'pass',
      },
      evidence: { upstreamProofResult: 'RPMX_HAXE_PLUGIN:PASS' },
    },
  }
}

function writeFixture(root, values, duplicateId = null) {
  for (const spec of PROOFS) {
    const directory = path.join(root, artifactName(spec, context))
    fs.mkdirSync(directory, { recursive: true })
    fs.writeFileSync(path.join(directory, evidenceArtifact), evidenceBody)
    fs.writeFileSync(path.join(directory, spec.summaryName), JSON.stringify(values[spec.id], null, 2) + '\n')
    if (spec.id === duplicateId) {
      const duplicate = path.join(directory, 'duplicate')
      fs.mkdirSync(duplicate)
      fs.writeFileSync(path.join(duplicate, spec.summaryName), JSON.stringify(values[spec.id], null, 2) + '\n')
    }
  }
}

function run(mutator = null, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-plugin-evidence-'))
  try {
    const values = fixtures()
    if (mutator) mutator(values)
    writeFixture(root, values, options.duplicateId)
    if (options.removeId) fs.rmSync(path.join(root, artifactName(PROOFS.find(spec => spec.id === options.removeId), context)), { recursive: true })
    if (options.removeEvidenceId) {
      const spec = PROOFS.find(item => item.id === options.removeEvidenceId)
      fs.rmSync(path.join(root, artifactName(spec, context), evidenceArtifact))
    }
    return evaluate({ ...context, artifactsDir: root, matrixResult: options.matrixResult || context.matrixResult })
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

function assertRejected(summary, fragment) {
  assert.deepStrictEqual(summary.emitted_markers, [])
  assert(summary.errors.some(error => error.includes(fragment)), `expected error containing ${fragment}; got ${summary.errors.join('; ')}`)
}

const valid = run()
assert.strictEqual(valid.schema, AGGREGATE_SCHEMA)
assert.strictEqual(valid.candidate_sha, context.candidateSha)
assert.strictEqual(valid.proofs.length, 3)
assert.deepStrictEqual(valid.errors, [])
assert.deepStrictEqual(valid.emitted_markers, [AGGREGATE_MARKER])
for (const proof of valid.proofs) {
  assert.strictEqual(proof.verified, true)
  assert(/^[0-9a-f]{64}$/.test(proof.summary_sha256))
}

assertRejected(run(null, { removeId: 'upstream-to-hxhx' }), 'missing artifact directory')
assertRejected(run(null, { duplicateId: 'hxhx-to-hxhx' }), 'must contain exactly one')
assertRejected(run(values => { values['upstream-to-hxhx'].route = 'wrong-route' }), 'expected route')
assertRejected(run(values => { values['hxhx-to-hxhx'].candidateSha = 'f'.repeat(40) }), 'candidate SHA mismatch')
assertRejected(run(values => { values['hxhx-to-hxhx'].pluginCompiler.stage0Forbidden = false }), 'did not forbid stage0')
assertRejected(run(values => { values['upstream-to-hxhx'].plugin.artifactSha256 = 'bad' }), 'SHA-256')
assertRejected(run(values => { values['upstream-to-hxhx'].plugin.artifactSha256 = 'f'.repeat(64) }), 'digest does not match')
assertRejected(run(null, { removeEvidenceId: 'hxhx-to-hxhx' }), 'missing plugin evidence artifact')
assertRejected(run(values => { values['upstream-host-adapter'].pluginArtifact.evidenceArtifact = '../outside.cmxs' }), 'must stay beside')
assertRejected(run(values => { values['hxhx-to-hxhx'].sampleCompile.runtimeStdout = 'wrong' }), 'generated program output')
assertRejected(run(values => { values['upstream-host-adapter'].synthetic = true }), 'authentic, not synthetic')
assertRejected(run(null, { matrixResult: 'failure' }), 'matrix result is failure')

console.log('FULL1_PLUGIN_PARITY_EVIDENCE_FIXTURES:PASS')
