#!/usr/bin/env node
/**
 * Network-free checks for selecting the exact RC run and artifact.
 */

const assert = require('assert')
const { validateHandoff } = require('./download-full1-rc-artifact')

const runId = 123456
const runAttempt = 2
const sha = 'a'.repeat(40)
const args = { runId, runAttempt, allowNoGo: false }
const run = {
  name: 'Gate Full1 RC / Release Go-No-Go',
  path: '.github/workflows/gate-full1-rc.yml',
  status: 'completed',
  conclusion: 'success',
  run_attempt: runAttempt,
  head_sha: sha
}
const artifact = {
  name: `full1-rc-summary-${runId}-${runAttempt}`,
  expired: false,
  digest: `sha256:${'b'.repeat(64)}`,
  expires_at: '2026-08-01T00:00:00Z',
  workflow_run: { id: runId, head_sha: sha }
}
const summary = {
  schema: 'full1-rc-summary.v2',
  evidenceTier: 10,
  synthetic: false,
  decision: 'go',
  marker: 'FULL1_RELEASE_GO:PASS',
  candidate: { sha, version: '1.0.0-rc.1' },
  rcWorkflow: {
    file: '.github/workflows/gate-full1-rc.yml',
    runId,
    runAttempt
  }
}
const now = new Date('2026-07-13T00:00:00Z')

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function main() {
  validateHandoff(run, artifact, summary, args, now)

  const wrongAttemptArtifact = clone(artifact)
  wrongAttemptArtifact.name = `full1-rc-summary-${runId}-1`
  assert.throws(
    () => validateHandoff(run, wrongAttemptArtifact, summary, args, now),
    /selected run attempt/
  )

  const crossShaSummary = clone(summary)
  crossShaSummary.candidate.sha = 'c'.repeat(40)
  assert.throws(
    () => validateHandoff(run, artifact, crossShaSummary, args, now),
    /candidate identity/
  )

  const expiredArtifact = clone(artifact)
  expiredArtifact.expires_at = '2026-07-12T00:00:00Z'
  assert.throws(
    () => validateHandoff(run, expiredArtifact, summary, args, now),
    /expiration/
  )

  const failedRun = clone(run)
  failedRun.conclusion = 'failure'
  const noGoSummary = clone(summary)
  noGoSummary.decision = 'no-go'
  noGoSummary.marker = 'FULL1_RELEASE_GO:FAIL'
  assert.throws(
    () => validateHandoff(failedRun, artifact, noGoSummary, args, now),
    /conclusion must be success/
  )
  validateHandoff(failedRun, artifact, noGoSummary, { ...args, allowNoGo: true }, now)

  assert.throws(
    () => validateHandoff(failedRun, artifact, summary, { ...args, allowNoGo: true }, now),
    /requires a successful RC workflow/
  )

  const synthetic = clone(summary)
  synthetic.synthetic = true
  assert.throws(
    () => validateHandoff(run, artifact, synthetic, args, now),
    /tier-10 evidence/
  )

  console.log('[download-full1-rc-artifact-fixture-test] ok')
}

main()
