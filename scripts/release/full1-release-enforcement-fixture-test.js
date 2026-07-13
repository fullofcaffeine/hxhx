#!/usr/bin/env node
/**
 * Synthetic coverage for candidate-bound Full1 semantic-release enforcement.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { deriveMarkers, evidenceContracts, rolePolicy } = require('../ci/full1-rc-gate')
const { requiredMarkers, sha256File } = require('./full1-release-enforcement')

const root = path.resolve(__dirname, '../..')
const script = path.join(root, 'scripts/release/full1-release-enforcement.js')
const scopeContractVersion = JSON.parse(
  fs.readFileSync(path.join(root, 'docs/02-user-guide/compat/full-1.0-scope.json'), 'utf8')
).contractVersion
const marker = 'FULL1_RELEASE_GO:PASS'
const candidateSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
const candidateVersion = '1.0.0-rc.1'
const runId = 424242
const runAttempt = 2
const now = '2026-07-13T08:00:00Z'

function run(version, env = {}) {
  return spawnSync(process.execPath, [script, version], {
    cwd: root,
    env: {
      ...process.env,
      FULL1_RELEASE_GO_MARKER: '',
      FULL1_RC_SUMMARY_JSON: '',
      FULL1_RELEASE_CANDIDATE_SHA: '',
      FULL1_RC_SOURCE_RUN_ID: '',
      FULL1_RC_SOURCE_RUN_ATTEMPT: '',
      FULL1_RC_ARTIFACT_ID: '',
      FULL1_RC_ARTIFACT_DIGEST: '',
      FULL1_RC_ARTIFACT_VERIFIED: '',
      FULL1_RELEASE_NOW: now,
      ...env
    },
    encoding: 'utf8'
  })
}

function assert(condition, message) {
  if (!condition) {
    console.error(`[full1-release-enforcement-fixture-test] ERROR: ${message}`)
    process.exit(1)
  }
}

function evidenceSource(id, role, markers, artifactId) {
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
    createdAt: '2026-07-13T07:00:00Z',
    expiresAt: '2026-07-27T07:00:00Z',
    evidenceTier: rolePolicy[role].tier,
    synthetic: false,
    valid: true,
    summary: {
      path: `${id}.summary.json`,
      digest: `sha256:${String(artifactId + 1000).padStart(64, '0')}`,
      schema: contract.summarySchema
    },
    markers,
    errors: [],
    accepted: true
  }
}

function validSummary() {
  const sources = [
    evidenceSource('policy', 'policy', rolePolicy.policy.markers, 1001),
    evidenceSource('gate3', 'gate3', rolePolicy.gate3.markers, 1002),
    ...rolePolicy.suite.markers.map((suiteMarker, index) => {
      const suite = ['misc', 'server', 'threads', 'optimization', 'display'][index]
      return evidenceSource(`suite-${suite}`, 'suite', [suiteMarker], 1010 + index)
    }),
    evidenceSource('macro', 'macro', rolePolicy.macro.markers, 1020),
    evidenceSource('eval', 'eval', rolePolicy.eval.markers, 1021),
    evidenceSource('plugin', 'plugin', rolePolicy.plugin.markers, 1022),
    evidenceSource('performance', 'performance', rolePolicy.performance.markers, 1023)
  ]
  const derived = deriveMarkers(sources)
  const required = requiredMarkers()
  return {
    schema: 'full1-rc-summary.v2',
    evidenceTier: 10,
    synthetic: false,
    decision: 'go',
    marker,
    candidate: {
      sha: candidateSha,
      version: candidateVersion
    },
    contract: {
      contractVersion: scopeContractVersion,
      haxeCompatibilityBaseline: '4.3.7',
      scopeManifest: 'docs/02-user-guide/compat/full-1.0-scope.json',
      scopeManifestDigest: sha256File('docs/02-user-guide/compat/full-1.0-scope.json'),
      parityMap: 'docs/00-project/PARITY_MAP_FULL_1_0.json',
      parityMapDigest: sha256File('docs/00-project/PARITY_MAP_FULL_1_0.json')
    },
    rcWorkflow: {
      name: 'Gate Full1 RC / Release Go-No-Go',
      file: '.github/workflows/gate-full1-rc.yml',
      runId,
      runAttempt,
      createdAt: '2026-07-13T06:45:00Z'
    },
    freshness: {
      evaluatedAt: '2026-07-13T07:30:00Z',
      maxAgeHours: 24
    },
    requiredMarkers: required,
    presentMarkers: required.filter(requiredMarker => derived.markers.has(requiredMarker)),
    missingMarkers: [],
    markerSources: derived.markerSources,
    derivedEvidence: derived.derived,
    evidenceSources: sources,
    missingArtifacts: [],
    invalidArtifacts: [],
    errors: []
  }
}

function writeSummary(dir, name, body) {
  const summaryPath = path.join(dir, `${name}.json`)
  fs.writeFileSync(summaryPath, `${JSON.stringify(body, null, 2)}\n`)
  return summaryPath
}

function validEnv(summaryPath, overrides = {}) {
  return {
    FULL1_RELEASE_GO_MARKER: marker,
    FULL1_RC_SUMMARY_JSON: summaryPath,
    FULL1_RELEASE_CANDIDATE_SHA: candidateSha,
    FULL1_RC_SOURCE_RUN_ID: String(runId),
    FULL1_RC_SOURCE_RUN_ATTEMPT: String(runAttempt),
    FULL1_RC_ARTIFACT_ID: '9999',
    FULL1_RC_ARTIFACT_DIGEST: `sha256:${'f'.repeat(64)}`,
    FULL1_RC_ARTIFACT_VERIFIED: '1',
    ...overrides
  }
}

function expectBlocked(result, snippet, label) {
  assert(result.status !== 0, `${label} unexpectedly passed`)
  assert(result.stderr.includes(snippet), `${label} did not report ${JSON.stringify(snippet)}\n${result.stderr}`)
}

function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-release-enforcement-v2-'))
  try {
    const pre1 = run('0.16.0')
    assert(pre1.status === 0, `0.x release should pass: ${pre1.stderr}`)
    assert(pre1.stdout.includes('FULL1_RELEASE_ENFORCEMENT:SKIP_PRE_1_0'), '0.x skip marker missing')

    expectBlocked(run('1.0.0'), 'FULL1_RELEASE_GO_MARKER', 'missing release marker')
    expectBlocked(
      run(candidateVersion, { FULL1_RELEASE_GO_MARKER: marker }),
      'FULL1_RC_SUMMARY_JSON',
      'missing summary'
    )

    const legacyPath = writeSummary(temp, 'legacy', {
      schema: 'full1-rc-summary.v1',
      marker,
      requiredMarkers: ['FULL1_PERF_PARITY:PASS'],
      missingMarkers: []
    })
    expectBlocked(run(candidateVersion, validEnv(legacyPath)), 'full1-rc-summary.v2', 'legacy v1 summary')

    const noGo = validSummary()
    noGo.decision = 'no-go'
    noGo.marker = 'FULL1_RELEASE_GO:FAIL'
    noGo.missingMarkers = ['FULL1_PERF_PARITY:PASS']
    const noGoPath = writeSummary(temp, 'no-go', noGo)
    expectBlocked(run(candidateVersion, validEnv(noGoPath)), 'decision=go', 'no-go summary')

    const wrongVersion = validSummary()
    wrongVersion.candidate.version = '1.0.0-rc.2'
    const wrongVersionPath = writeSummary(temp, 'wrong-version', wrongVersion)
    expectBlocked(run(candidateVersion, validEnv(wrongVersionPath)), 'candidate version', 'version mismatch')

    const wrongSha = validSummary()
    wrongSha.candidate.sha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    const wrongShaPath = writeSummary(temp, 'wrong-sha', wrongSha)
    expectBlocked(run(candidateVersion, validEnv(wrongShaPath)), 'candidate SHA', 'SHA mismatch')

    const wrongManifest = validSummary()
    wrongManifest.contract.parityMapDigest = `sha256:${'c'.repeat(64)}`
    const wrongManifestPath = writeSummary(temp, 'wrong-manifest', wrongManifest)
    expectBlocked(run(candidateVersion, validEnv(wrongManifestPath)), 'manifest paths/digests', 'manifest mismatch')

    const synthetic = validSummary()
    synthetic.evidenceSources[0].synthetic = true
    const syntheticPath = writeSummary(temp, 'synthetic', synthetic)
    expectBlocked(run(candidateVersion, validEnv(syntheticPath)), 'synthetic evidence', 'synthetic source')

    const stale = validSummary()
    stale.evidenceSources[0].createdAt = '2026-07-10T07:00:00Z'
    const stalePath = writeSummary(temp, 'stale', stale)
    expectBlocked(run(candidateVersion, validEnv(stalePath)), 'stale or from the future', 'stale source')

    const tampered = validSummary()
    tampered.evidenceSources[0].artifactDigest = 'sha256:not-valid'
    const tamperedPath = writeSummary(temp, 'tampered', tampered)
    expectBlocked(run(candidateVersion, validEnv(tamperedPath)), 'artifactDigest is invalid', 'tampered source')

    const wrongArtifactName = validSummary()
    wrongArtifactName.evidenceSources.find(source => source.id === 'plugin').artifactName = 'full1-plugin-parity-summary-424242-1'
    const wrongArtifactNamePath = writeSummary(temp, 'wrong-artifact-name', wrongArtifactName)
    expectBlocked(
      run(candidateVersion, validEnv(wrongArtifactNamePath)),
      'artifact name must be',
      'wrong-attempt child artifact'
    )

    const wrongMarkers = validSummary()
    wrongMarkers.requiredMarkers = wrongMarkers.requiredMarkers.slice(1)
    const wrongMarkersPath = writeSummary(temp, 'wrong-markers', wrongMarkers)
    expectBlocked(run(candidateVersion, validEnv(wrongMarkersPath)), 'requiredMarkers[]', 'marker manifest mismatch')

    const wrongMarkerSources = validSummary()
    wrongMarkerSources.markerSources['FULL1_PERF_PARITY:PASS'] = ['policy']
    const wrongMarkerSourcesPath = writeSummary(temp, 'wrong-marker-sources', wrongMarkerSources)
    expectBlocked(
      run(candidateVersion, validEnv(wrongMarkerSourcesPath)),
      'markerSources does not match',
      'tampered marker sources'
    )

    const good = validSummary()
    const goodPath = writeSummary(temp, 'good', good)
    expectBlocked(
      run(candidateVersion, validEnv(goodPath, { FULL1_RC_ARTIFACT_VERIFIED: '' })),
      'did not verify',
      'unverified downloaded artifact'
    )
    expectBlocked(
      run(candidateVersion, validEnv(goodPath, { FULL1_RC_SOURCE_RUN_ID: '999' })),
      'run identity',
      'wrong RC source run'
    )

    const allowed = run(candidateVersion, validEnv(goodPath))
    assert(allowed.status === 0, `valid candidate-bound RC should pass: ${allowed.stderr}`)
    assert(allowed.stdout.includes('FULL1_RELEASE_ENFORCEMENT:PASS'), 'valid RC pass marker missing')

    const invalidVersion = run('v1.0.0')
    assert(invalidVersion.status !== 0, 'invalid semver should fail')

    console.log('[full1-release-enforcement-fixture-test] ok')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
