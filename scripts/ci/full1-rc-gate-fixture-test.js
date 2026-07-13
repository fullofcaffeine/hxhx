#!/usr/bin/env node
/**
 * Synthetic contract tests for candidate-bound Full1 RC provenance.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { evidenceContracts, rolePolicy, sha256File } = require('./full1-rc-gate')

const root = path.resolve(__dirname, '../..')
const scopePath = path.join(root, 'docs/02-user-guide/compat/full-1.0-scope.json')
const parityMapPath = path.join(root, 'docs/00-project/PARITY_MAP_FULL_1_0.json')
const scriptPath = path.join(root, 'scripts/ci/full1-rc-gate.js')
const releaseMarker = 'FULL1_RELEASE_GO:PASS'
const candidateSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
const candidateVersion = '1.0.0-rc.1'
const runId = 424242
const runAttempt = 2
const now = '2026-07-13T08:00:00Z'

function fail(message) {
  console.error(`[full1-rc-gate-fixture-test] ${message}`)
  process.exit(1)
}

function assert(condition, message) {
  if (!condition) fail(message)
}

function source(id, role, markers, artifactId, overrides = {}) {
  const contract = evidenceContracts[id]
  return {
    id,
    role,
    workflow: `Fixture ${role}`,
    workflowFile: contract.workflowFile,
    workflowConclusion: 'success',
    runId,
    runAttempt,
    headSha: candidateSha,
    artifactId,
    artifactName: `${contract.artifactPrefix}-${runId}-${runAttempt}`,
    artifactDigest: `sha256:${String(artifactId).padStart(64, '0')}`,
    createdAt: '2026-07-13T07:15:00Z',
    expiresAt: '2026-07-27T07:15:00Z',
    evidenceTier: rolePolicy[role].tier,
    synthetic: false,
    valid: true,
    summary: {
      path: `${id}.summary.json`,
      digest: `sha256:${String(artifactId + 1000).padStart(64, '0')}`,
      schema: contract.summarySchema
    },
    markers,
    ...overrides
  }
}

function completeIndex() {
  const suiteMarkers = rolePolicy.suite.markers
  const sources = [
    source('policy', 'policy', rolePolicy.policy.markers, 1001),
    source('gate3', 'gate3', rolePolicy.gate3.markers, 1002),
    ...suiteMarkers.map((marker, index) => {
      const suite = ['misc', 'server', 'threads', 'optimization', 'display'][index]
      return source(`suite-${suite}`, 'suite', [marker], 1010 + index)
    }),
    source('macro', 'macro', rolePolicy.macro.markers, 1020),
    source('eval', 'eval', rolePolicy.eval.markers, 1021),
    source('plugin', 'plugin', rolePolicy.plugin.markers, 1022),
    source('performance', 'performance', rolePolicy.performance.markers, 1023)
  ]
  return {
    schema: 'full1-rc-evidence-index.v1',
    synthetic: false,
    candidate: {
      sha: candidateSha,
      version: candidateVersion
    },
    contract: {
      scopeManifestDigest: sha256File(scopePath),
      parityMapDigest: sha256File(parityMapPath)
    },
    rcWorkflow: {
      runId,
      runAttempt,
      createdAt: '2026-07-13T07:00:00Z'
    },
    collectedAt: '2026-07-13T07:30:00Z',
    missingArtifacts: [],
    invalidArtifacts: [],
    sources
  }
}

function runCase(tmpDir, name, index, extraArgs = []) {
  const caseDir = path.join(tmpDir, name)
  fs.mkdirSync(caseDir, { recursive: true })
  const evidencePath = path.join(caseDir, 'evidence-index.json')
  const summaryPath = path.join(caseDir, 'full1-rc.summary.json')
  fs.writeFileSync(evidencePath, `${JSON.stringify(index, null, 2)}\n`)
  const args = [
    scriptPath,
    '--evidence-index', evidencePath,
    '--candidate-sha', candidateSha,
    '--candidate-version', candidateVersion,
    '--run-id', String(runId),
    '--run-attempt', String(runAttempt),
    '--now', now,
    '--max-age-hours', '24',
    '--json-out', summaryPath,
    ...extraArgs
  ]
  const result = spawnSync(process.execPath, args, { cwd: root, encoding: 'utf8' })
  const summary = fs.existsSync(summaryPath) ? JSON.parse(fs.readFileSync(summaryPath, 'utf8')) : null
  return { result, summary }
}

function expectNoGo(testCase, snippet, label) {
  assert(testCase.result.status !== 0, `${label} unexpectedly passed`)
  assert(testCase.summary && testCase.summary.decision === 'no-go', `${label} did not write a no-go summary`)
  const text = [
    testCase.result.stderr,
    ...(testCase.summary.errors || []),
    ...(testCase.summary.missingMarkers || [])
  ].join('\n')
  assert(text.includes(snippet), `${label} did not report ${JSON.stringify(snippet)}\n${text}`)
  assert(!testCase.result.stdout.includes(releaseMarker), `${label} printed ${releaseMarker}`)
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-rc-v2-'))
  try {
    const all = completeIndex()
    const pass = runCase(tmpDir, 'pass', all)
    assert(pass.result.status === 0, `pass case failed: ${pass.result.stderr}`)
    assert(pass.result.stdout.includes(releaseMarker), 'pass case did not emit release marker')
    assert(pass.summary.schema === 'full1-rc-summary.v2', 'pass case did not write v2 schema')
    assert(pass.summary.decision === 'go', 'pass case did not record go')
    assert(pass.summary.missingMarkers.length === 0, 'pass case retained missing markers')
    assert(pass.summary.evidenceSources.every(item => item.accepted), 'pass case has rejected sources')
    assert(pass.summary.derivedEvidence.some(item => item.marker === 'FULL1_SUITE_MATRIX:PASS'), 'suite aggregate was not derived')
    assert(pass.summary.derivedEvidence.some(item => item.marker === 'FULL1_MACRO_EVAL_PARITY:PASS'), 'macro/eval aggregate was not derived')

    const missingPerf = completeIndex()
    missingPerf.sources = missingPerf.sources.filter(item => item.role !== 'performance')
    expectNoGo(runCase(tmpDir, 'missing-perf', missingPerf), 'FULL1_PERF_PARITY:PASS', 'missing performance evidence')

    const crossSha = completeIndex()
    crossSha.sources.find(item => item.role === 'plugin').headSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    expectNoGo(runCase(tmpDir, 'cross-sha', crossSha), 'source SHA does not match', 'cross-SHA evidence')

    const wrongVersion = completeIndex()
    wrongVersion.candidate.version = '1.0.0-rc.2'
    expectNoGo(runCase(tmpDir, 'wrong-version', wrongVersion), 'candidate version mismatch', 'cross-version evidence')

    const wrongManifest = completeIndex()
    wrongManifest.contract.scopeManifestDigest = `sha256:${'c'.repeat(64)}`
    expectNoGo(runCase(tmpDir, 'wrong-manifest', wrongManifest), 'manifest digest mismatch', 'manifest mismatch')

    const synthetic = completeIndex()
    synthetic.sources.find(item => item.role === 'suite').synthetic = true
    expectNoGo(runCase(tmpDir, 'synthetic', synthetic), 'synthetic evidence is forbidden', 'synthetic evidence')

    const stale = completeIndex()
    stale.sources.find(item => item.role === 'gate3').createdAt = '2026-07-10T07:00:00Z'
    expectNoGo(runCase(tmpDir, 'stale', stale), 'artifact is stale', 'stale artifact')

    const tampered = completeIndex()
    tampered.sources.find(item => item.role === 'plugin').artifactDigest = 'sha256:not-a-digest'
    expectNoGo(runCase(tmpDir, 'tampered', tampered), 'artifactDigest must be', 'tampered artifact metadata')

    const wrongAttemptArtifact = completeIndex()
    wrongAttemptArtifact.sources.find(item => item.role === 'plugin').artifactName = `full1-plugin-parity-summary-${runId}-1`
    expectNoGo(
      runCase(tmpDir, 'wrong-attempt-artifact', wrongAttemptArtifact),
      `artifact name must be full1-plugin-parity-summary-${runId}-${runAttempt}`,
      'wrong-attempt artifact'
    )

    const cancelled = completeIndex()
    cancelled.sources.find(item => item.role === 'macro').workflowConclusion = 'cancelled'
    expectNoGo(runCase(tmpDir, 'cancelled', cancelled), 'workflow conclusion must be success', 'cancelled child workflow')

    const invalidArtifact = completeIndex()
    invalidArtifact.invalidArtifacts.push('full1-plugin-summary: digest mismatch')
    expectNoGo(runCase(tmpDir, 'invalid-artifact', invalidArtifact), 'invalid artifacts', 'collector rejection')

    const typedAggregate = completeIndex()
    typedAggregate.sources.find(item => item.role === 'suite').markers.push('FULL1_SUITE_MATRIX:PASS')
    expectNoGo(runCase(tmpDir, 'typed-aggregate', typedAggregate), 'cannot emit FULL1_SUITE_MATRIX:PASS', 'manually supplied aggregate')

    const legacy = spawnSync(process.execPath, [scriptPath, '--marker', 'FULL1_PERF_PARITY:PASS'], {
      cwd: root,
      encoding: 'utf8'
    })
    assert(legacy.status !== 0, 'legacy --marker input unexpectedly passed')
    assert(legacy.stderr.includes('unknown argument: --marker'), 'legacy marker failure was not explicit')

    console.log('[full1-rc-gate-fixture-test] ok')
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

main()
