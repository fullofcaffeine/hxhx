#!/usr/bin/env node
/**
 * Synthetic contract tests for the CI evidence ownership evaluator.
 */

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = process.cwd()
const evaluator = path.join(repoRoot, 'scripts/ci/ci-evidence-ownership.js')
const productionManifestPath = path.join(repoRoot, 'docs/00-project/CI_EVIDENCE_OWNERSHIP.json')
const productionBeadsPath = path.join(repoRoot, '.beads/issues.jsonl')
const fixedNow = '2026-07-13T07:00:00Z'
const fixtureHead = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

function fail(message) {
  console.error(`[ci-evidence-ownership-fixture-test] ERROR: ${message}`)
  process.exit(1)
}

function assert(condition, message) {
  if (!condition) fail(message)
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function runEvaluator(manifestPath, beadsPath, snapshotPath, jsonOut = null) {
  const args = [
    evaluator,
    '--manifest', manifestPath,
    '--beads', beadsPath,
    '--snapshot', snapshotPath,
    '--now', fixedNow
  ]
  if (jsonOut) args.push('--json-out', jsonOut)
  return childProcess.spawnSync(process.execPath, args, {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function syntheticRun(check, id, overrides = {}) {
  return {
    id,
    name: check.name,
    event: check.events[0],
    status: 'completed',
    conclusion: 'success',
    headSha: check.kind === 'required' ? fixtureHead : 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    attempt: 1,
    createdAt: '2026-07-13T06:00:00Z',
    updatedAt: '2026-07-13T06:10:00Z',
    url: `https://github.com/example/hxhx/actions/runs/${id}`,
    ...overrides
  }
}

function baselineSnapshot(manifest) {
  const runs = {}
  let id = 99000000000
  const openRequiredIncident = manifest.incidents.find(incident => {
    if (incident.state !== 'open' || !incident.run) return false
    const check = manifest.checks.find(candidate => candidate.id === incident.checkId)
    return check && check.kind === 'required'
  })
  const baselineHead = openRequiredIncident ? openRequiredIncident.run.headSha : fixtureHead
  for (const check of manifest.checks) {
    const incident = manifest.incidents.find(candidate => (
      candidate.state === 'open' && candidate.checkId === check.id
    ))
    if (incident && incident.run) {
      runs[check.id] = [{
        ...incident.run,
        name: check.name,
        status: 'completed'
      }]
    } else if (check.kind === 'required') {
      runs[check.id] = [syntheticRun(check, id++, { headSha: baselineHead })]
    } else if (incident && incident.evidenceState === 'missing') {
      runs[check.id] = []
    } else {
      runs[check.id] = [syntheticRun(check, id++)]
    }
  }
  return {
    schema: 'hxhx.ci-run-snapshot.v1',
    repository: 'example/hxhx',
    defaultBranch: 'main',
    headSha: baselineHead,
    headCreatedAt: '2026-07-13T05:30:00Z',
    observedAt: fixedNow,
    runs
  }
}

function expectFailure(result, snippet, label) {
  assert(result.status !== 0, `${label} unexpectedly passed`)
  assert(result.stderr.includes(snippet), `${label} did not report ${JSON.stringify(snippet)}\n${result.stderr}`)
}

function main() {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-ci-evidence-ownership-'))
  try {
    const manifest = JSON.parse(fs.readFileSync(productionManifestPath, 'utf8'))
    const baseSnapshot = baselineSnapshot(manifest)
    const baseSnapshotPath = path.join(tmpDir, 'baseline.snapshot.json')
    writeJson(baseSnapshotPath, baseSnapshot)

    const baseline = runEvaluator(productionManifestPath, productionBeadsPath, baseSnapshotPath)
    assert(baseline.status === 0, `production ownership ledger did not validate\n${baseline.stderr}`)
    assert(baseline.stdout.includes('CI_EVIDENCE_OWNERSHIP:PASS'), 'baseline pass marker is missing')

    const core = manifest.checks.find(check => check.id === 'core-pr')
    assert(core, 'production manifest is missing core-pr')
    const noOpenCoreManifest = structuredClone(manifest)
    noOpenCoreManifest.incidents = noOpenCoreManifest.incidents.filter(incident => (
      incident.state !== 'open' || incident.checkId !== core.id
    ))
    const noOpenCoreManifestPath = path.join(tmpDir, 'no-open-core.manifest.json')
    writeJson(noOpenCoreManifestPath, noOpenCoreManifest)

    const unowned = structuredClone(baseSnapshot)
    unowned.runs[core.id] = [syntheticRun(core, 99100000001, {
      conclusion: 'failure',
      headSha: baseSnapshot.headSha
    })]
    const unownedPath = path.join(tmpDir, 'unowned.snapshot.json')
    writeJson(unownedPath, unowned)
    expectFailure(
      runEvaluator(noOpenCoreManifestPath, productionBeadsPath, unownedPath),
      'has no matching open P0/P1 incident',
      'unowned required failure'
    )

    const ownedManifest = structuredClone(noOpenCoreManifest)
    const ownedRun = syntheticRun(core, 99100000002, {
      conclusion: 'failure',
      headSha: baseSnapshot.headSha
    })
    ownedManifest.incidents.push({
      id: 'fixture-owned-core',
      checkId: core.id,
      state: 'open',
      evidenceState: 'failure-current',
      failureClass: 'semantic',
      bead: 'fixture-owner',
      recordedAt: fixedNow,
      run: {
        id: ownedRun.id,
        attempt: ownedRun.attempt,
        headSha: ownedRun.headSha,
        event: ownedRun.event,
        conclusion: ownedRun.conclusion,
        createdAt: ownedRun.createdAt,
        updatedAt: ownedRun.updatedAt,
        url: ownedRun.url
      },
      reproductionOrEvidence: 'A synthetic required workflow reports one deterministic semantic failure.',
      closureGate: 'A later exact-head required workflow run must complete successfully.'
    })
    const ownedManifestPath = path.join(tmpDir, 'owned.manifest.json')
    writeJson(ownedManifestPath, ownedManifest)
    const ownedBeadsPath = path.join(tmpDir, 'owned.issues.jsonl')
    const ownerComment = [
      'fixture-owned-core',
      String(ownedRun.id),
      ownedRun.headSha,
      'semantic',
      'closure gate: a later exact-head required workflow run must pass'
    ].join(' ')
    fs.writeFileSync(ownedBeadsPath, `${fs.readFileSync(productionBeadsPath, 'utf8').trim()}\n${JSON.stringify({
      id: 'fixture-owner',
      title: 'Synthetic fixture owner',
      status: 'open',
      priority: 0,
      comments: [{ text: ownerComment }]
    })}\n`)
    const owned = structuredClone(baseSnapshot)
    owned.runs[core.id] = [ownedRun]
    const ownedPath = path.join(tmpDir, 'owned.snapshot.json')
    writeJson(ownedPath, owned)
    const ownedResult = runEvaluator(ownedManifestPath, ownedBeadsPath, ownedPath)
    assert(ownedResult.status === 0, `owned required failure did not pass\n${ownedResult.stderr}`)

    const cancelled = structuredClone(baseSnapshot)
    cancelled.runs[core.id] = [syntheticRun(core, 99100000003, {
      conclusion: 'cancelled',
      headSha: baseSnapshot.headSha
    })]
    const cancelledPath = path.join(tmpDir, 'cancelled.snapshot.json')
    writeJson(cancelledPath, cancelled)
    expectFailure(
      runEvaluator(noOpenCoreManifestPath, productionBeadsPath, cancelledPath),
      'cancelled-no-successor',
      'cancelled run without successor'
    )

    const superseded = structuredClone(baseSnapshot)
    superseded.runs[core.id] = [
      syntheticRun(core, 99100000004, {
        conclusion: 'cancelled',
        headSha: baseSnapshot.headSha,
        createdAt: '2026-07-13T05:40:00Z',
        updatedAt: '2026-07-13T05:50:00Z'
      }),
      syntheticRun(core, 99100000005, {
        headSha: baseSnapshot.headSha,
        createdAt: '2026-07-13T06:20:00Z',
        updatedAt: '2026-07-13T06:30:00Z'
      })
    ]
    const supersededPath = path.join(tmpDir, 'superseded.snapshot.json')
    const supersededReportPath = path.join(tmpDir, 'superseded.report.json')
    writeJson(supersededPath, superseded)
    const supersededResult = runEvaluator(
      noOpenCoreManifestPath,
      productionBeadsPath,
      supersededPath,
      supersededReportPath
    )
    assert(supersededResult.status === 0, `cancelled run with a green successor failed\n${supersededResult.stderr}`)
    const supersededReport = JSON.parse(fs.readFileSync(supersededReportPath, 'utf8'))
    const supersededFinding = supersededReport.findings.find(finding => finding.checkId === core.id)
    assert(
      supersededFinding.supersededCancellations[0].state === 'cancelled-superseded',
      'superseded cancellation is not machine-readable in the report'
    )

    const gate1 = manifest.checks.find(check => check.id === 'gate1-weekly')
    assert(gate1, 'production manifest is missing gate1-weekly')
    assert(
      gate1.events.includes('schedule') && gate1.events.includes('workflow_dispatch'),
      'Gate 1 evidence must accept both its scheduled and enabled manual routes'
    )
    const gate2 = manifest.checks.find(check => check.id === 'gate2-weekly')
    assert(gate2, 'production manifest is missing gate2-weekly')
    assert(
      gate2.events.includes('schedule') && gate2.events.includes('workflow_dispatch'),
      'Gate 2 evidence must accept both its scheduled and enabled manual routes'
    )
    const noOpenGate1Manifest = structuredClone(manifest)
    noOpenGate1Manifest.incidents = noOpenGate1Manifest.incidents.filter(incident => (
      incident.state !== 'open' || incident.checkId !== gate1.id
    ))
    const noOpenGate1ManifestPath = path.join(tmpDir, 'no-open-gate1.manifest.json')
    writeJson(noOpenGate1ManifestPath, noOpenGate1Manifest)
    const manualGate1Success = structuredClone(baseSnapshot)
    manualGate1Success.runs[gate1.id] = [
      syntheticRun(gate1, 99100000006, {
        event: 'schedule',
        conclusion: 'failure',
        createdAt: '2026-07-13T05:00:00Z',
        updatedAt: '2026-07-13T05:10:00Z'
      }),
      syntheticRun(gate1, 99100000007, {
        event: 'workflow_dispatch',
        createdAt: '2026-07-13T06:00:00Z',
        updatedAt: '2026-07-13T06:10:00Z'
      })
    ]
    const manualGate1SuccessPath = path.join(tmpDir, 'manual-gate1-success.snapshot.json')
    writeJson(manualGate1SuccessPath, manualGate1Success)
    const manualGate1SuccessResult = runEvaluator(
      noOpenGate1ManifestPath,
      productionBeadsPath,
      manualGate1SuccessPath
    )
    assert(
      manualGate1SuccessResult.status === 0,
      `newer successful manual Gate 1 run did not supersede the scheduled failure\n${manualGate1SuccessResult.stderr}`
    )

    const skippedManualGate1 = structuredClone(baseSnapshot)
    skippedManualGate1.runs[gate1.id] = [syntheticRun(gate1, 99100000008, {
      event: 'workflow_dispatch',
      conclusion: 'skipped'
    })]
    const skippedManualGate1Path = path.join(tmpDir, 'skipped-manual-gate1.snapshot.json')
    writeJson(skippedManualGate1Path, skippedManualGate1)
    expectFailure(
      runEvaluator(productionManifestPath, productionBeadsPath, skippedManualGate1Path),
      'failure-current',
      'skipped manual Gate 1 run'
    )

    const stale = structuredClone(baseSnapshot)
    stale.runs[gate1.id] = [syntheticRun(gate1, 99100000009, {
      createdAt: '2026-06-20T06:00:00Z',
      updatedAt: '2026-06-20T06:10:00Z'
    })]
    const stalePath = path.join(tmpDir, 'stale.snapshot.json')
    writeJson(stalePath, stale)
    expectFailure(
      runEvaluator(productionManifestPath, productionBeadsPath, stalePath),
      'stale-success',
      'stale scheduled success'
    )

    const crossSha = structuredClone(baseSnapshot)
    crossSha.headCreatedAt = '2026-07-13T01:00:00Z'
    crossSha.runs[core.id] = [syntheticRun(core, 99100000010, {
      headSha: 'cccccccccccccccccccccccccccccccccccccccc'
    })]
    const crossShaPath = path.join(tmpDir, 'cross-sha.snapshot.json')
    writeJson(crossShaPath, crossSha)
    expectFailure(
      runEvaluator(noOpenCoreManifestPath, productionBeadsPath, crossShaPath),
      'no qualifying run',
      'cross-SHA required success'
    )

    const closedBeadsPath = path.join(tmpDir, 'closed-owner.issues.jsonl')
    const closedLines = fs.readFileSync(ownedBeadsPath, 'utf8').trim().split(/\r?\n/)
    const fixtureIssue = JSON.parse(closedLines.pop())
    fixtureIssue.status = 'closed'
    fs.writeFileSync(closedBeadsPath, `${closedLines.join('\n')}\n${JSON.stringify(fixtureIssue)}\n`)
    expectFailure(
      runEvaluator(ownedManifestPath, closedBeadsPath, ownedPath),
      'must be active while the incident is open',
      'closed incident owner'
    )

    const lowPriorityBeadsPath = path.join(tmpDir, 'p2-owner.issues.jsonl')
    fixtureIssue.status = 'open'
    fixtureIssue.priority = 2
    fs.writeFileSync(lowPriorityBeadsPath, `${closedLines.join('\n')}\n${JSON.stringify(fixtureIssue)}\n`)
    expectFailure(
      runEvaluator(ownedManifestPath, lowPriorityBeadsPath, ownedPath),
      'must be P0 or P1',
      'P2 incident owner'
    )

    console.log('[ci:guards] OK: CI evidence ownership synthetic fixtures pass')
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

main()
