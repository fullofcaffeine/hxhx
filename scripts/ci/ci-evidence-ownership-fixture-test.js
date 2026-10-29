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

/**
 * Replay times for an open stale-success incident.
 *
 * The baseline replays each open incident's exact run so the evaluator can
 * match it to its owner. Matching uses the run id, attempt, and SHA, not its
 * timestamps. These fixtures evaluate at the fixed clock `fixedNow`, which
 * can be earlier than a real incident's run. An exact copy of a stale run
 * would then look fresh, and the baseline would report a "newer success"
 * instead of the stale state that the incident records. Move only the
 * replayed timestamps to just outside the check's freshness window at
 * `fixedNow`. Other evidence states keep their recorded times.
 */
function staleReplayTimes(check, incident) {
  if (incident.evidenceState !== 'stale-success') return {}
  const updatedMs = Date.parse(fixedNow) - (check.freshnessHours + 1) * 3600000
  return {
    createdAt: new Date(updatedMs - 600000).toISOString(),
    updatedAt: new Date(updatedMs).toISOString()
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
        ...staleReplayTimes(check, incident),
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

    // An open stale-success incident whose real run is newer than the fixed
    // fixture clock must still validate in the baseline replay.
    const kpi = manifest.checks.find(check => check.id === 'kpi-manual-weekly')
    assert(kpi && kpi.kind === 'release-evidence', 'production manifest is missing kpi-manual-weekly')
    const staleOwnedManifest = structuredClone(manifest)
    staleOwnedManifest.incidents = staleOwnedManifest.incidents.filter(incident => (
      incident.state !== 'open' || incident.checkId !== kpi.id
    ))
    const staleOwnedRun = syntheticRun(kpi, 99100000011, {
      createdAt: '2026-08-16T00:15:38Z',
      updatedAt: '2026-08-16T00:19:05Z'
    })
    staleOwnedManifest.incidents.push({
      id: 'fixture-stale-kpi',
      checkId: kpi.id,
      state: 'open',
      evidenceState: 'stale-success',
      failureClass: 'repository-policy',
      bead: 'fixture-stale-owner',
      recordedAt: fixedNow,
      run: {
        id: staleOwnedRun.id,
        attempt: staleOwnedRun.attempt,
        headSha: staleOwnedRun.headSha,
        event: staleOwnedRun.event,
        conclusion: staleOwnedRun.conclusion,
        createdAt: staleOwnedRun.createdAt,
        updatedAt: staleOwnedRun.updatedAt,
        url: staleOwnedRun.url
      },
      reproductionOrEvidence: 'A synthetic manual report succeeded but is older than its freshness window.',
      closureGate: 'A later manual report run must complete successfully within the freshness window.'
    })
    const staleOwnedManifestPath = path.join(tmpDir, 'stale-owned.manifest.json')
    writeJson(staleOwnedManifestPath, staleOwnedManifest)
    const staleOwnedBeadsPath = path.join(tmpDir, 'stale-owned.issues.jsonl')
    fs.writeFileSync(staleOwnedBeadsPath, `${fs.readFileSync(productionBeadsPath, 'utf8').trim()}\n${JSON.stringify({
      id: 'fixture-stale-owner',
      title: 'Synthetic stale report owner',
      status: 'open',
      priority: 1,
      comments: [{
        text: ['fixture-stale-kpi', String(staleOwnedRun.id), staleOwnedRun.headSha, 'repository-policy'].join(' ')
      }]
    })}\n`)
    const staleOwnedSnapshotPath = path.join(tmpDir, 'stale-owned.snapshot.json')
    const staleOwnedReportPath = path.join(tmpDir, 'stale-owned.report.json')
    writeJson(staleOwnedSnapshotPath, baselineSnapshot(staleOwnedManifest))
    const staleOwnedResult = runEvaluator(
      staleOwnedManifestPath,
      staleOwnedBeadsPath,
      staleOwnedSnapshotPath,
      staleOwnedReportPath
    )
    assert(
      staleOwnedResult.status === 0,
      `baseline replay of an open stale-success incident did not validate\n${staleOwnedResult.stderr}`
    )
    const staleOwnedFinding = JSON.parse(fs.readFileSync(staleOwnedReportPath, 'utf8')).findings
      .find(finding => finding.checkId === kpi.id)
    assert(
      staleOwnedFinding.state === 'stale-success' && staleOwnedFinding.ownerIncident === 'fixture-stale-kpi',
      'baseline replay must observe the open stale-success incident as stale and owned'
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

    signatureFixtures(manifest, baseSnapshot, tmpDir)

    console.log('[ci:guards] OK: CI evidence ownership synthetic fixtures pass')
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

/**
 * A failure signature lets one open incident own a required check's failure
 * on later main commits. It must match the failing job, the failing step, and
 * one log line. Every other case still needs a new owner.
 */
function signatureFixtures(manifest, baseSnapshot, tmpDir) {
  const lite = manifest.checks.find(check => check.id === 'gate1-lite-pr')
  assert(lite && lite.kind === 'required', 'production manifest is missing gate1-lite-pr')
  const signature = {
    job: 'Fixture macro smoke',
    step: 'Run fixture macro smoke',
    logPattern: 'Fixture.hx:7:3: value loop requires a resolved iterator protocol'
  }
  const oldSha = 'dddddddddddddddddddddddddddddddddddddddd'
  const originalRun = syntheticRun(lite, 99200000001, {
    conclusion: 'failure',
    headSha: oldSha,
    createdAt: '2026-07-12T06:00:00Z',
    updatedAt: '2026-07-12T06:10:00Z'
  })
  const baseManifest = structuredClone(manifest)
  baseManifest.incidents = baseManifest.incidents.filter(incident => (
    incident.state !== 'open' || incident.checkId !== lite.id
  ))
  function incidentFor(withSignature) {
    const incident = {
      id: 'fixture-lite-signature',
      checkId: lite.id,
      state: 'open',
      evidenceState: 'failure-current',
      failureClass: 'semantic',
      bead: 'fixture-lite-owner',
      recordedAt: fixedNow,
      run: {
        id: originalRun.id,
        attempt: originalRun.attempt,
        headSha: originalRun.headSha,
        event: originalRun.event,
        conclusion: originalRun.conclusion,
        createdAt: originalRun.createdAt,
        updatedAt: originalRun.updatedAt,
        url: originalRun.url
      },
      reproductionOrEvidence: 'A synthetic required smoke stops at one known typing diagnostic on every commit.',
      closureGate: 'An exact-head required smoke run on main must complete successfully.'
    }
    if (withSignature) incident.failureSignature = structuredClone(signature)
    return incident
  }
  function writeCase(name, incident) {
    const caseManifest = structuredClone(baseManifest)
    caseManifest.incidents.push(incident)
    const manifestPath = path.join(tmpDir, `${name}.manifest.json`)
    writeJson(manifestPath, caseManifest)
    return manifestPath
  }
  const signedManifestPath = writeCase('lite-signed', incidentFor(true))
  const unsignedManifestPath = writeCase('lite-unsigned', incidentFor(false))
  const beadsPath = path.join(tmpDir, 'lite-owner.issues.jsonl')
  fs.writeFileSync(beadsPath, `${fs.readFileSync(productionBeadsPath, 'utf8').trim()}\n${JSON.stringify({
    id: 'fixture-lite-owner',
    title: 'Synthetic required smoke owner',
    status: 'in_progress',
    priority: 1,
    comments: [{
      text: ['fixture-lite-signature', String(originalRun.id), oldSha, 'semantic', signature.logPattern].join(' ')
    }]
  })}\n`)

  const matchingLog = [
    '2026-07-13T06:05:00.0000000Z == Gate 1 (stage3 no-emit rung)',
    `2026-07-13T06:05:01.0000000Z hxhx(stage3): type failed: /src/Fixture.hx: /src/${signature.logPattern}`,
    '2026-07-13T06:05:01.1000000Z ##[error]Process completed with exit code 2.'
  ].join('\n')
  function newerRun(id, failedJobs) {
    const run = syntheticRun(lite, id, { conclusion: 'failure', headSha: baseSnapshot.headSha })
    if (failedJobs !== undefined) run.failedJobs = failedJobs
    return run
  }
  function evaluateCase(name, manifestPath, run, headSha = baseSnapshot.headSha) {
    const snapshot = structuredClone(baseSnapshot)
    snapshot.headSha = headSha
    snapshot.runs[lite.id] = [run]
    const snapshotPath = path.join(tmpDir, `${name}.snapshot.json`)
    const reportPath = path.join(tmpDir, `${name}.report.json`)
    writeJson(snapshotPath, snapshot)
    const result = runEvaluator(manifestPath, beadsPath, snapshotPath, reportPath)
    const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
    return { result, finding: report.findings.find(finding => finding.checkId === lite.id) }
  }
  const unowned = 'has no matching open P0/P1 incident'

  const matched = evaluateCase('lite-match', signedManifestPath, newerRun(99200000002, [
    { name: signature.job, failedSteps: [signature.step], log: matchingLog }
  ]))
  assert(matched.result.status === 0, `matching failure signature on a newer commit was not owned\n${matched.result.stderr}`)
  assert(
    matched.finding.ownerIncident === 'fixture-lite-signature'
      && matched.finding.ownerMatch === 'failure-signature'
      && matched.finding.run.id === 99200000002
      && matched.finding.run.headSha === baseSnapshot.headSha,
    'report must identify the run that the failure signature matched'
  )

  const exact = evaluateCase('lite-exact', signedManifestPath, {
    ...originalRun,
    headSha: baseSnapshot.headSha
  })
  expectFailure(exact.result, unowned, 'signed incident replay with a changed SHA')

  expectFailure(
    evaluateCase('lite-other-message', signedManifestPath, newerRun(99200000003, [
      { name: signature.job, failedSteps: [signature.step], log: matchingLog.replace('Fixture.hx:7:3', 'Fixture.hx:9:1') }
    ])).result,
    unowned,
    'different failure message'
  )
  expectFailure(
    evaluateCase('lite-no-evidence', signedManifestPath, newerRun(99200000004)).result,
    unowned,
    'run without fetched failure evidence'
  )
  expectFailure(
    evaluateCase('lite-null-log', signedManifestPath, newerRun(99200000005, [
      { name: signature.job, failedSteps: [signature.step], log: null }
    ])).result,
    unowned,
    'failed job whose log could not be read'
  )
  expectFailure(
    evaluateCase('lite-other-job', signedManifestPath, newerRun(99200000006, [
      { name: 'Another job', failedSteps: [signature.step], log: matchingLog }
    ])).result,
    unowned,
    'different failing job'
  )
  expectFailure(
    evaluateCase('lite-other-step', signedManifestPath, newerRun(99200000007, [
      { name: signature.job, failedSteps: ['Install toolchain'], log: matchingLog }
    ])).result,
    unowned,
    'different failing step'
  )
  expectFailure(
    evaluateCase('lite-extra-job', signedManifestPath, newerRun(99200000008, [
      { name: signature.job, failedSteps: [signature.step], log: matchingLog },
      { name: 'Another job', failedSteps: ['Run other check'], log: 'unrelated failure' }
    ])).result,
    unowned,
    'additional unrelated failing job'
  )
  expectFailure(
    evaluateCase('lite-duplicate-job', signedManifestPath, newerRun(99200000013, [
      { name: signature.job, failedSteps: [signature.step], log: matchingLog },
      { name: signature.job, failedSteps: [signature.step], log: matchingLog }
    ])).result,
    unowned,
    'two identically named failed jobs'
  )
  expectFailure(
    evaluateCase('lite-two-steps', signedManifestPath, newerRun(99200000014, [
      { name: signature.job, failedSteps: [signature.step, 'Upload logs'], log: matchingLog }
    ])).result,
    unowned,
    'signature job with a second failed step'
  )
  expectFailure(
    evaluateCase('lite-no-jobs', signedManifestPath, newerRun(99200000009, [])).result,
    unowned,
    'failed run with no failed job'
  )
  expectFailure(
    evaluateCase('lite-older-run', signedManifestPath, {
      ...newerRun(99200000010, [{ name: signature.job, failedSteps: [signature.step], log: matchingLog }]),
      createdAt: '2026-07-11T06:00:00Z',
      updatedAt: '2026-07-11T06:10:00Z'
    }).result,
    unowned,
    'run older than the signed incident'
  )
  const cancelled = newerRun(99200000011, [
    { name: signature.job, failedSteps: [signature.step], log: matchingLog }
  ])
  cancelled.conclusion = 'cancelled'
  expectFailure(
    evaluateCase('lite-cancelled', signedManifestPath, cancelled).result,
    unowned,
    'cancelled run with a matching log'
  )
  expectFailure(
    evaluateCase('lite-unsigned', unsignedManifestPath, newerRun(99200000012, [
      { name: signature.job, failedSteps: [signature.step], log: matchingLog }
    ])).result,
    unowned,
    'incident without a signature on a newer commit'
  )
  const unsignedExact = evaluateCase('lite-unsigned-exact', unsignedManifestPath, originalRun, oldSha)
  assert(
    unsignedExact.result.status === 0
      && unsignedExact.finding.ownerIncident === 'fixture-lite-signature'
      && unsignedExact.finding.ownerMatch === 'exact-run',
    `incident without a signature must still own its exact run\n${unsignedExact.result.stderr}`
  )

  const badSignature = incidentFor(true)
  badSignature.failureSignature = { job: signature.job, step: '', logPattern: 'short' }
  expectFailure(
    runEvaluator(writeCase('lite-bad-signature', badSignature), beadsPath, path.join(tmpDir, 'lite-match.snapshot.json')),
    'failureSignature.step is required',
    'incomplete failure signature'
  )
  const paddedSignature = incidentFor(true)
  paddedSignature.failureSignature.logPattern = `  ${signature.logPattern}`
  expectFailure(
    runEvaluator(writeCase('lite-padded-signature', paddedSignature), beadsPath, path.join(tmpDir, 'lite-match.snapshot.json')),
    'must not start or end with whitespace',
    'failure signature with surrounding whitespace'
  )
  const unrecordedBeadsPath = path.join(tmpDir, 'lite-unrecorded.issues.jsonl')
  const beadLines = fs.readFileSync(beadsPath, 'utf8').trim().split(/\r?\n/)
  const owner = JSON.parse(beadLines.pop())
  owner.comments = [{ text: owner.comments[0].text.replace(signature.logPattern, '') }]
  fs.writeFileSync(unrecordedBeadsPath, `${beadLines.join('\n')}\n${JSON.stringify(owner)}\n`)
  expectFailure(
    runEvaluator(signedManifestPath, unrecordedBeadsPath, path.join(tmpDir, 'lite-match.snapshot.json')),
    'must record failure signature',
    'bead without the signature text'
  )
}

/**
 * The live collector reads job metadata and job logs only for a signature
 * candidate. A read failure must leave the run without evidence so that it
 * stays unowned.
 */
async function liveFailureEvidenceFixtures() {
  const { collectFailedJobs } = require('./ci-evidence-ownership')
  const apiRoot = 'https://api.example.test/repos/example/hxhx'
  const run = { id: 77, attempt: 2 }
  const jobsPayload = {
    total_count: 2,
    jobs: [
      { id: 1, name: 'Passing job', conclusion: 'success', steps: [{ name: 'ok', conclusion: 'success' }] },
      {
        id: 2,
        name: 'Failing job',
        conclusion: 'failure',
        steps: [
          { name: 'Setup', conclusion: 'success' },
          { name: 'Run smoke', conclusion: 'failure' }
        ]
      }
    ]
  }
  const requested = []
  const ok = await collectFailedJobs(apiRoot, run, 'token', {
    json: async url => { requested.push(url); return jobsPayload },
    text: async url => { requested.push(url); return 'line one\nknown failure line\n' }
  })
  assert(
    ok.error === null
      && ok.failedJobs.length === 1
      && ok.failedJobs[0].name === 'Failing job'
      && ok.failedJobs[0].failedSteps.join(',') === 'Run smoke'
      && ok.failedJobs[0].log.includes('known failure line'),
    `live collector did not build failed-job evidence: ${JSON.stringify(ok)}`
  )
  assert(requested[0] === `${apiRoot}/actions/runs/77/attempts/2/jobs?per_page=100`, `unexpected jobs URL ${requested[0]}`)
  assert(requested[1] === `${apiRoot}/actions/jobs/2/logs`, `unexpected log URL ${requested[1]}`)

  const logFailure = await collectFailedJobs(apiRoot, run, 'token', {
    json: async () => jobsPayload,
    text: async () => { throw new Error('GitHub API read failed: http-410') }
  })
  assert(
    logFailure.failedJobs === null && /http-410/.test(logFailure.error),
    'an unreadable job log must leave the run without failure evidence'
  )
  const jobsFailure = await collectFailedJobs(apiRoot, run, 'token', {
    json: async () => { throw new Error('GitHub API read failed: http-404') },
    text: async () => 'unused'
  })
  assert(jobsFailure.failedJobs === null, 'an unreadable job list must leave the run without failure evidence')
  const truncated = await collectFailedJobs(apiRoot, run, 'token', {
    json: async () => ({ ...jobsPayload, total_count: 101 }),
    text: async () => 'unused'
  })
  assert(truncated.failedJobs === null, 'an incomplete job list must leave the run without failure evidence')

  // Candidate selection uses the evaluator's own run selection.
  const { attachSignatureEvidence } = require('./ci-evidence-ownership')
  const manifest = JSON.parse(fs.readFileSync(productionManifestPath, 'utf8'))
  const lite = manifest.checks.find(check => check.id === 'gate1-lite-pr')
  const headSha = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
  const recorded = syntheticRun(lite, 99300000001, { conclusion: 'failure', headSha })
  const signedManifest = {
    checks: [lite],
    incidents: [{
      id: 'fixture-live-signature',
      checkId: lite.id,
      state: 'open',
      evidenceState: 'failure-current',
      run: { id: recorded.id, attempt: recorded.attempt, headSha, createdAt: recorded.createdAt },
      failureSignature: { job: 'Fixture job', step: 'Fixture step', logPattern: 'Fixture.hx:1:1: fixture failure text' }
    }]
  }
  function liveSnapshot(runs) {
    return { headSha, headCreatedAt: '2026-07-13T05:30:00Z', runs: { [lite.id]: runs } }
  }
  const calls = []
  const collect = async run => {
    calls.push(run.id)
    return { failedJobs: [{ name: 'Fixture job', failedSteps: ['Fixture step'], log: 'x' }], error: null }
  }
  const nowMs = Date.parse(fixedNow)
  await attachSignatureEvidence(signedManifest, liveSnapshot([structuredClone(recorded)]), nowMs, collect)
  assert(calls.length === 0, 'live audit fetched evidence for the exact recorded run')
  await attachSignatureEvidence(signedManifest, liveSnapshot([
    syntheticRun(lite, 99300000002, { headSha, createdAt: '2026-07-13T06:20:00Z', updatedAt: '2026-07-13T06:30:00Z' })
  ]), nowMs, collect)
  assert(calls.length === 0, 'live audit fetched evidence for a successful run')
  const newer = syntheticRun(lite, 99300000003, {
    conclusion: 'failure',
    headSha,
    createdAt: '2026-07-13T06:20:00Z',
    updatedAt: '2026-07-13T06:30:00Z'
  })
  const newerSnapshot = liveSnapshot([structuredClone(recorded), newer])
  await attachSignatureEvidence(signedManifest, newerSnapshot, nowMs, collect)
  assert(calls.join(',') === '99300000003', `live audit must fetch evidence only for the newer failing run: ${calls}`)
  assert(
    Array.isArray(newerSnapshot.runs[lite.id][1].failedJobs) && newerSnapshot.runs[lite.id][0].failedJobs === undefined,
    'live audit must attach evidence to the selected run only'
  )
  const failing = async () => ({ failedJobs: null, error: 'GitHub API read failed: http-410' })
  const failedSnapshot = liveSnapshot([newer])
  await attachSignatureEvidence(signedManifest, failedSnapshot, nowMs, failing)
  assert(
    failedSnapshot.runs[lite.id][0].failedJobs === null
      && /http-410/.test(failedSnapshot.runs[lite.id][0].failureEvidenceError),
    'live audit must record a failed evidence read as no evidence'
  )
  console.log('[ci:guards] OK: CI evidence ownership live failure evidence fails closed')
}

main()
liveFailureEvidenceFixtures().catch(error => fail(error.stack || error.message))
