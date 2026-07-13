#!/usr/bin/env node
/**
 * Focused, network-free checks for Full1 RC child-artifact validation.
 */

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const {
  expectedArtifacts,
  findSummary,
  safeExtract,
  validateSummary
} = require('./full1-rc-artifact-collector')

const context = {
  runId: 123456,
  runAttempt: 3,
  candidateSha: 'a'.repeat(40),
  candidateVersion: '1.0.0-rc.1'
}
const gate3Targets = ['Macro', 'Js', 'Neko', 'Hl', 'Python', 'Java', 'Cs', 'Cpp', 'Lua', 'Php']

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function specById(id) {
  const spec = expectedArtifacts(context).find(item => item.id === id)
  assert(spec, `missing fixture spec ${id}`)
  return spec
}

function validFixtures() {
  return {
    policy: {
      schema: 'full1-rc-policy-evidence.v1',
      synthetic: false,
      candidate: { sha: context.candidateSha, version: context.candidateVersion },
      run: { id: context.runId, attempt: context.runAttempt },
      markers: [
        'FULL1_TARGET_SCOPE_CONTRACT:PASS',
        'FULL1_PARITY_MAP:PASS',
        'FULL1_MACRO_EVAL_CONTRACT:PASS',
        'FULL1_PLUGIN_PARITY_CONTRACT:PASS',
        'FULL1_FLAKE_POLICY:PASS',
        'FULL1_PERF_POLICY:PASS'
      ],
      results: [
        'FULL1_TARGET_SCOPE_CONTRACT:PASS',
        'FULL1_PARITY_MAP:PASS',
        'FULL1_MACRO_EVAL_CONTRACT:PASS',
        'FULL1_PLUGIN_PARITY_CONTRACT:PASS',
        'FULL1_FLAKE_POLICY:PASS',
        'FULL1_PERF_POLICY:PASS'
      ].map(marker => ({ marker, exitCode: 0, markerObserved: true }))
    },
    gate3: {
      schema: 'gate3-extended-summary.v1',
      strict_no_skip: true,
      targets_requested: gate3Targets,
      targets_ran: gate3Targets,
      targets_skipped: [],
      targets_failed: [],
      targets_missing: []
    },
    'suite-misc': {
      schema: 'full1-upstream-suite-summary.v1',
      suite: 'misc',
      strict: true,
      marker: 'FULL1_SUITE_MISC:PASS',
      exit_code: 0,
      commands: [{ exit_code: 0, signal: null }]
    },
    macro: {
      schema: 'macro-runtime-parity-summary.v2',
      run_id: String(context.runId),
      run_attempt: String(context.runAttempt),
      jobs: { macro_runtime_parity: { result: 'success' } },
      emitted_markers: ['MACRO_RUNTIME_PARITY_WEEKLY:PASS', 'FULL1_MACRO_PARITY:PASS']
    },
    eval: {
      schema: 'full1-eval-native-summary.v1',
      marker: 'FULL1_EVAL_NATIVE:PASS',
      eval_context: { stage0_forbidden: true },
      result: { exit_code: 0 }
    },
    plugin: {
      schema: 'full1-plugin-parity-summary.v3',
      synthetic: false,
      candidate_sha: context.candidateSha,
      run_id: String(context.runId),
      run_attempt: String(context.runAttempt),
      jobs: { full1_plugin_proofs: { result: 'success' } },
      required_markers: [
        'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS',
        'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS',
        'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS'
      ],
      proofs: [
        ['upstream-to-hxhx', 'full1-plugin-upstream-to-hxhx', 'REFLAXE_OCAML_PLUGIN_UPSTREAM_TO_HXHX:PASS'],
        ['hxhx-to-hxhx', 'full1-plugin-hxhx-to-hxhx', 'REFLAXE_OCAML_PLUGIN_HXHX_TO_HXHX:PASS'],
        ['upstream-host-adapter', 'full1-plugin-upstream-host-adapter', 'REFLAXE_OCAML_PLUGIN_UPSTREAM_HOST_ADAPTER:PASS']
      ].map(([id, prefix, marker]) => ({
        id,
        artifact_name: `${prefix}-${context.runId}-${context.runAttempt}`,
        summary_schema: 'full1-plugin-proof.v1',
        summary_sha256: 'b'.repeat(64),
        plugin_artifact_sha256: 'c'.repeat(64),
        marker,
        verified: true
      })),
      errors: [],
      emitted_markers: ['FULL1_PLUGIN_PARITY:PASS']
    },
    performance: {
      schema: 'full1-perf-evaluation.v1',
      decision: 'pass',
      marker: 'FULL1_PERF_PARITY:PASS',
      failures: []
    }
  }
}

function testArtifactInventory() {
  const specs = expectedArtifacts(context)
  assert.strictEqual(specs.length, 11)
  assert.strictEqual(expectedArtifacts(context, true).length, 1)
  for (const spec of specs) {
    assert(
      spec.artifactName.endsWith(`-${context.runId}-${context.runAttempt}`),
      `${spec.id} artifact name does not include the exact run attempt`
    )
  }
}

function testSummaryValidation() {
  const fixtures = validFixtures()
  for (const [id, summary] of Object.entries(fixtures)) {
    const result = validateSummary(specById(id), summary, context)
    assert(result.schema)
    assert(Array.isArray(result.markers) && result.markers.length > 0)
  }

  const syntheticPolicy = clone(fixtures.policy)
  syntheticPolicy.synthetic = true
  assert.throws(
    () => validateSummary(specById('policy'), syntheticPolicy, context),
    /synthetic/
  )

  const skippedGate3 = clone(fixtures.gate3)
  skippedGate3.targets_skipped.push('Js')
  assert.throws(
    () => validateSummary(specById('gate3'), skippedGate3, context),
    /targets_skipped/
  )

  const partialSuite = clone(fixtures['suite-misc'])
  partialSuite.commands[0].exit_code = 1
  assert.throws(
    () => validateSummary(specById('suite-misc'), partialSuite, context),
    /did not complete successfully/
  )

  const cancelledMacro = clone(fixtures.macro)
  cancelledMacro.jobs.macro_runtime_parity.result = 'cancelled'
  assert.throws(
    () => validateSummary(specById('macro'), cancelledMacro, context),
    /did not succeed/
  )

  const claimedMacro = clone(fixtures.macro)
  claimedMacro.emitted_markers = []
  assert.throws(
    () => validateSummary(specById('macro'), claimedMacro, context),
    /did not emit/
  )

  const delegatedEval = clone(fixtures.eval)
  delegatedEval.eval_context.stage0_forbidden = false
  assert.throws(
    () => validateSummary(specById('eval'), delegatedEval, context),
    /stage0-forbidden/
  )

  const wrongPluginAttempt = clone(fixtures.plugin)
  wrongPluginAttempt.run_attempt = '2'
  assert.throws(
    () => validateSummary(specById('plugin'), wrongPluginAttempt, context),
    /run identity mismatch/
  )

  const claimedPlugin = clone(fixtures.plugin)
  claimedPlugin.emitted_markers = []
  assert.throws(
    () => validateSummary(specById('plugin'), claimedPlugin, context),
    /did not emit/
  )

  const crossCandidatePlugin = clone(fixtures.plugin)
  crossCandidatePlugin.candidate_sha = 'f'.repeat(40)
  assert.throws(
    () => validateSummary(specById('plugin'), crossCandidatePlugin, context),
    /candidate identity/
  )

  const unverifiedPlugin = clone(fixtures.plugin)
  unverifiedPlugin.proofs[1].verified = false
  assert.throws(
    () => validateSummary(specById('plugin'), unverifiedPlugin, context),
    /unverified/
  )

  const wrongPluginProofSchema = clone(fixtures.plugin)
  wrongPluginProofSchema.proofs[0].summary_schema = 'full1-plugin-proof.v0'
  assert.throws(
    () => validateSummary(specById('plugin'), wrongPluginProofSchema, context),
    /invalid provenance/
  )

  const failedPerformance = clone(fixtures.performance)
  failedPerformance.decision = 'fail'
  assert.throws(
    () => validateSummary(specById('performance'), failedPerformance, context),
    /did not pass/
  )
}

function testZipExtraction() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-full1-collector-'))
  try {
    const sourceDir = path.join(tmpDir, 'source')
    const extractDir = path.join(tmpDir, 'extract')
    const zipPath = path.join(tmpDir, 'artifact.zip')
    fs.mkdirSync(sourceDir)
    fs.writeFileSync(path.join(sourceDir, 'summary.json'), '{}\n')
    const zipped = spawnSync('zip', ['-q', zipPath, 'summary.json'], {
      cwd: sourceDir,
      encoding: 'utf8'
    })
    assert.strictEqual(zipped.status, 0, zipped.stderr)
    safeExtract(zipPath, extractDir)
    assert.strictEqual(findSummary(extractDir, 'summary.json'), path.join(extractDir, 'summary.json'))

    fs.mkdirSync(path.join(extractDir, 'duplicate'))
    fs.writeFileSync(path.join(extractDir, 'duplicate', 'summary.json'), '{}\n')
    assert.throws(() => findSummary(extractDir, 'summary.json'), /found 2/)
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

function main() {
  testArtifactInventory()
  testSummaryValidation()
  testZipExtraction()
  console.log('[full1-rc-artifact-collector-fixture-test] ok')
}

main()
