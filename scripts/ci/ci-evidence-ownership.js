#!/usr/bin/env node
/**
 * Check that important CI failures have a real, active Beads owner.
 *
 * The policy file says which workflows matter. A run snapshot says what
 * GitHub observed. This evaluator joins those facts with the tracked Beads
 * export and refuses an unowned failure, cancellation, stale success, or
 * missing scheduled run.
 *
 * An incident normally owns one exact run (id, attempt, and commit). An open
 * incident may also declare a `failureSignature`: the failing job name, the
 * failing step name, and a literal text that must appear in one line of that
 * job's log. A newer failing run on main is then owned by that incident only
 * when its only failure is that job and step and the log line is present.
 * Missing or unreadable logs never count as a match.
 */

const fs = require('fs')
const path = require('path')
const { githubJson, githubText } = require('./github-api-json')

const defaultManifestPath = 'docs/00-project/CI_EVIDENCE_OWNERSHIP.json'
const defaultBeadsPath = '.beads/issues.jsonl'
const ciGatesPath = 'docs/00-project/CI_GATES.md'
const auditWorkflowPath = '.github/workflows/ci-evidence-ownership.yml'
const packagePath = 'package.json'
const passMarker = 'CI_EVIDENCE_OWNERSHIP:PASS'

function parseArgs(argv) {
  const args = {
    manifest: defaultManifestPath,
    beads: defaultBeadsPath,
    snapshot: null,
    live: false,
    repository: process.env.GITHUB_REPOSITORY || null,
    headSha: null,
    now: null,
    jsonOut: null
  }
  for (let i = 0; i < argv.length; i++) {
    const value = argv[i]
    if (value === '--live') args.live = true
    else if (value === '--manifest') args.manifest = argv[++i]
    else if (value === '--beads') args.beads = argv[++i]
    else if (value === '--snapshot') args.snapshot = argv[++i]
    else if (value === '--repository') args.repository = argv[++i]
    else if (value === '--head-sha') args.headSha = argv[++i]
    else if (value === '--now') args.now = argv[++i]
    else if (value === '--json-out') args.jsonOut = argv[++i]
    else throw new Error(`unknown argument: ${value}`)
  }
  if (args.live && args.snapshot) throw new Error('choose either --live or --snapshot, not both')
  if (!args.live && !args.snapshot) throw new Error('one of --live or --snapshot is required')
  return args
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function readIssues(filePath) {
  const issues = new Map()
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/)
  for (const line of lines) {
    if (!line.trim()) continue
    const issue = JSON.parse(line)
    if (issue.id) issues.set(issue.id, issue)
  }
  return issues
}

function issueSearchText(issue) {
  const comments = Array.isArray(issue.comments) ? issue.comments.map(comment => comment.text || '') : []
  return [issue.title, issue.description, issue.acceptance_criteria, issue.notes, ...comments]
    .filter(Boolean)
    .join('\n')
}

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim().length > 0
}

function validDate(value) {
  return nonEmptyString(value) && !Number.isNaN(Date.parse(value))
}

function validSha(value) {
  return typeof value === 'string' && /^[0-9a-f]{40}$/i.test(value)
}

function workflowName(filePath) {
  const text = fs.readFileSync(filePath, 'utf8')
  const match = text.match(/^name:\s*(.+?)\s*$/m)
  if (!match) return null
  return match[1].replace(/^['"]|['"]$/g, '')
}

function validateRun(run, label, errors) {
  if (!run || typeof run !== 'object') {
    errors.push(`${label} must define a run object`)
    return
  }
  if (!Number.isInteger(run.id) || run.id <= 0) errors.push(`${label}.id must be a positive integer`)
  if (!Number.isInteger(run.attempt) || run.attempt <= 0) {
    errors.push(`${label}.attempt must be a positive integer`)
  }
  if (!validSha(run.headSha)) errors.push(`${label}.headSha must be a full 40-character commit SHA`)
  if (!nonEmptyString(run.event)) errors.push(`${label}.event is required`)
  if (!nonEmptyString(run.conclusion)) errors.push(`${label}.conclusion is required`)
  if (!validDate(run.createdAt)) errors.push(`${label}.createdAt must be an ISO timestamp`)
  if (!validDate(run.updatedAt)) errors.push(`${label}.updatedAt must be an ISO timestamp`)
  if (!nonEmptyString(run.url) || !String(run.url).includes(`/runs/${run.id}`)) {
    errors.push(`${label}.url must identify run ${run.id}`)
  }
}

function validateManifest(manifest, issues, manifestPath = defaultManifestPath) {
  const errors = []
  if (manifest.schema !== 'hxhx.ci-evidence-ownership.v1') {
    errors.push(`${manifestPath} schema must be hxhx.ci-evidence-ownership.v1`)
  }
  if (!nonEmptyString(manifest.policy) || !fs.existsSync(manifest.policy)) {
    errors.push(`${manifestPath} must reference an existing policy document`)
  }
  if (!nonEmptyString(manifest.defaultBranch)) errors.push(`${manifestPath} defaultBranch is required`)
  if (!Array.isArray(manifest.failureClasses) || manifest.failureClasses.length === 0) {
    errors.push(`${manifestPath} failureClasses[] must be non-empty`)
  }
  if (!Array.isArray(manifest.evidenceStates) || manifest.evidenceStates.length === 0) {
    errors.push(`${manifestPath} evidenceStates[] must be non-empty`)
  }
  if (!Array.isArray(manifest.checks) || manifest.checks.length === 0) {
    errors.push(`${manifestPath} checks[] must be non-empty`)
    return errors
  }

  const ciGates = fs.existsSync(ciGatesPath) ? fs.readFileSync(ciGatesPath, 'utf8') : ''
  const policy = nonEmptyString(manifest.policy) && fs.existsSync(manifest.policy)
    ? fs.readFileSync(manifest.policy, 'utf8')
    : ''
  const auditWorkflow = fs.existsSync(auditWorkflowPath)
    ? fs.readFileSync(auditWorkflowPath, 'utf8')
    : ''
  const packageJson = fs.existsSync(packagePath) ? readJson(packagePath) : null
  if (!policy.includes(defaultManifestPath)) {
    errors.push(`${manifest.policy} must explain ${defaultManifestPath}`)
  }
  if (!policy.includes(passMarker)) errors.push(`${manifest.policy} must explain ${passMarker}`)
  if (!ciGates.includes(defaultManifestPath)) {
    errors.push(`${ciGatesPath} must reference ${defaultManifestPath}`)
  }
  if (!ciGates.includes(passMarker)) errors.push(`${ciGatesPath} must explain ${passMarker}`)
  if (!auditWorkflow.includes('scripts/ci/ci-evidence-ownership.js')
    || !auditWorkflow.includes('--live')) {
    errors.push(`${auditWorkflowPath} must run the live CI evidence ownership audit`)
  }
  if (!auditWorkflow.includes('timeout-minutes: 10')
    || !auditWorkflow.includes('cancel-in-progress: true')) {
    errors.push(`${auditWorkflowPath} must keep the live audit bounded and cancel superseded runs`)
  }
  if (!packageJson || !packageJson.scripts
    || packageJson.scripts['guard:ci-evidence-ownership']
      !== 'node scripts/ci/ci-evidence-ownership-fixture-test.js && node scripts/ci/github-api-json-fixture-test.js') {
    errors.push(`${packagePath} must expose guard:ci-evidence-ownership`)
  }
  const checks = new Map()
  for (let index = 0; index < manifest.checks.length; index++) {
    const check = manifest.checks[index]
    const label = `${manifestPath} checks[${index}]`
    if (!nonEmptyString(check.id)) errors.push(`${label}.id is required`)
    else if (checks.has(check.id)) errors.push(`${label}.id is duplicated: ${check.id}`)
    else checks.set(check.id, check)
    if (!nonEmptyString(check.name)) errors.push(`${label}.name is required`)
    if (!nonEmptyString(check.workflow) || !fs.existsSync(check.workflow)) {
      errors.push(`${label}.workflow must reference an existing workflow file`)
    } else {
      const declaredName = workflowName(check.workflow)
      if (declaredName !== check.name) {
        errors.push(`${label}.name must match ${check.workflow} (${declaredName || 'missing name'})`)
      }
    }
    if (check.kind !== 'required' && check.kind !== 'release-evidence') {
      errors.push(`${label}.kind must be required or release-evidence`)
    }
    if (!Array.isArray(check.events) || check.events.length === 0) {
      errors.push(`${label}.events[] must be non-empty`)
    }
    if (check.kind === 'required'
      && (!Number.isInteger(check.missingGraceMinutes) || check.missingGraceMinutes < 1)) {
      errors.push(`${label}.missingGraceMinutes must be a positive integer`)
    }
    if (check.kind === 'release-evidence'
      && (!Number.isInteger(check.freshnessHours) || check.freshnessHours < 1)) {
      errors.push(`${label}.freshnessHours must be a positive integer`)
    }
    if (nonEmptyString(check.name) && !ciGates.includes(check.name)) {
      errors.push(`${label}.name must also appear in ${ciGatesPath}`)
    }
    if (nonEmptyString(check.name) && !auditWorkflow.includes(check.name)) {
      errors.push(`${auditWorkflowPath} must watch ${check.name}`)
    }
  }

  if (!Array.isArray(manifest.incidents)) {
    errors.push(`${manifestPath} incidents[] must be an array`)
    return errors
  }
  const incidentIds = new Set()
  const openChecks = new Set()
  for (let index = 0; index < manifest.incidents.length; index++) {
    const incident = manifest.incidents[index]
    const label = `${manifestPath} incidents[${index}]`
    if (!nonEmptyString(incident.id)) errors.push(`${label}.id is required`)
    else if (incidentIds.has(incident.id)) errors.push(`${label}.id is duplicated: ${incident.id}`)
    else incidentIds.add(incident.id)
    const check = checks.get(incident.checkId)
    if (!check) errors.push(`${label}.checkId does not name a declared check: ${incident.checkId}`)
    if (!['open', 'resolved', 'superseded'].includes(incident.state)) {
      errors.push(`${label}.state must be open, resolved, or superseded`)
    }
    if (!manifest.evidenceStates.includes(incident.evidenceState)) {
      errors.push(`${label}.evidenceState is not declared: ${incident.evidenceState}`)
    }
    if (!manifest.failureClasses.includes(incident.failureClass)) {
      errors.push(`${label}.failureClass is not declared: ${incident.failureClass}`)
    }
    if (!validDate(incident.recordedAt)) errors.push(`${label}.recordedAt must be an ISO timestamp`)
    if (!nonEmptyString(incident.reproductionOrEvidence)
      || incident.reproductionOrEvidence.trim().length < 20) {
      errors.push(`${label}.reproductionOrEvidence must explain the observed problem`)
    }
    if (!nonEmptyString(incident.closureGate) || incident.closureGate.trim().length < 20) {
      errors.push(`${label}.closureGate must explain what remote evidence closes the incident`)
    }
    if (incident.failureSignature !== undefined) {
      validateFailureSignature(incident, label, errors)
    }
    if (incident.evidenceState === 'missing') {
      if (incident.run !== null) errors.push(`${label}.run must be null for missing evidence`)
    } else {
      validateRun(incident.run, `${label}.run`, errors)
      if (check && incident.run && !check.events.includes(incident.run.event)) {
        errors.push(`${label}.run.event is not accepted by check ${check.id}`)
      }
    }

    const issue = issues.get(incident.bead)
    if (!issue) {
      errors.push(`${label}.bead does not exist in ${defaultBeadsPath}: ${incident.bead}`)
    } else {
      if (!Number.isInteger(issue.priority) || issue.priority > 1) {
        errors.push(`${label}.bead must be P0 or P1: ${incident.bead}`)
      }
      if (incident.state === 'open' && !['open', 'in_progress'].includes(issue.status)) {
        errors.push(`${label}.bead must be active while the incident is open: ${incident.bead}`)
      }
      if (incident.state === 'resolved' && issue.status !== 'closed') {
        errors.push(`${label}.bead must be closed when the incident is resolved: ${incident.bead}`)
      }
      const record = issueSearchText(issue)
      if (!record.includes(incident.id)) {
        errors.push(`${label}.bead must contain the ownership record id ${incident.id}`)
      }
      if (incident.run && !record.includes(String(incident.run.id))) {
        errors.push(`${label}.bead must record run ${incident.run.id}`)
      }
      if (incident.run && !record.includes(incident.run.headSha)) {
        errors.push(`${label}.bead must record failing SHA ${incident.run.headSha}`)
      }
      if (!record.includes(incident.failureClass)) {
        errors.push(`${label}.bead must record failure class ${incident.failureClass}`)
      }
      const signature = incident.failureSignature
      if (signature && nonEmptyString(signature.logPattern) && !record.includes(signature.logPattern)) {
        errors.push(`${label}.bead must record failure signature ${JSON.stringify(signature.logPattern)}`)
      }
    }

    if (incident.state === 'open') {
      if (openChecks.has(incident.checkId)) {
        errors.push(`${label}: only one latest open incident is allowed per check`)
      }
      openChecks.add(incident.checkId)
    } else if (incident.state === 'resolved') {
      const resolution = incident.resolution
      if (!resolution || resolution.conclusion !== 'success') {
        errors.push(`${label}.resolution must identify a successful successor run`)
      } else {
        if (!Number.isInteger(resolution.runId) || resolution.runId <= 0) {
          errors.push(`${label}.resolution.runId must be a positive integer`)
        }
        if (!Number.isInteger(resolution.runAttempt) || resolution.runAttempt <= 0) {
          errors.push(`${label}.resolution.runAttempt must be a positive integer`)
        }
        if (!validSha(resolution.headSha)) errors.push(`${label}.resolution.headSha must be a full SHA`)
        if (!validDate(resolution.resolvedAt)) {
          errors.push(`${label}.resolution.resolvedAt must be an ISO timestamp`)
        }
        if (!nonEmptyString(resolution.url)
          || !String(resolution.url).includes(`/runs/${resolution.runId}`)) {
          errors.push(`${label}.resolution.url must identify the successful run`)
        }
      }
    } else if (incident.state === 'superseded') {
      if (!incident.supersededBy || !Number.isInteger(incident.supersededBy.runId)) {
        errors.push(`${label}.supersededBy must identify the newer run`)
      }
    }
  }
  return errors
}

function validateFailureSignature(incident, label, errors) {
  const signature = incident.failureSignature
  const owner = `${label}.failureSignature`
  if (!signature || typeof signature !== 'object' || Array.isArray(signature)) {
    errors.push(`${owner} must be an object`)
    return
  }
  const allowed = new Set(['job', 'step', 'logPattern'])
  for (const key of Object.keys(signature)) {
    if (!allowed.has(key)) errors.push(`${owner}.${key} is not a recognized field`)
  }
  if (!nonEmptyString(signature.job)) errors.push(`${owner}.job is required`)
  if (!nonEmptyString(signature.step)) errors.push(`${owner}.step is required`)
  if (!nonEmptyString(signature.logPattern) || signature.logPattern.length < 20) {
    errors.push(`${owner}.logPattern must be a literal log text of at least 20 characters`)
  } else if (/[\r\n]/.test(signature.logPattern)) {
    errors.push(`${owner}.logPattern must fit on one log line`)
  } else if (signature.logPattern.trim() !== signature.logPattern) {
    errors.push(`${owner}.logPattern must not start or end with whitespace`)
  }
  if (incident.evidenceState !== 'failure-current' || !incident.run) {
    errors.push(`${owner} is only allowed on a failure-current incident with a recorded run`)
  }
}

function normalizeRun(run) {
  return {
    id: Number(run.id ?? run.databaseId),
    name: run.name ?? run.workflowName,
    event: run.event,
    status: run.status,
    conclusion: run.conclusion || null,
    headSha: run.headSha ?? run.head_sha,
    attempt: Number(run.attempt ?? run.run_attempt ?? 1),
    createdAt: run.createdAt ?? run.created_at,
    updatedAt: run.updatedAt ?? run.updated_at,
    url: run.url ?? run.html_url,
    failedJobs: Array.isArray(run.failedJobs) ? run.failedJobs : null,
    failureEvidenceError: nonEmptyString(run.failureEvidenceError) ? run.failureEvidenceError : null
  }
}

function newestRun(runs) {
  return [...runs].sort((left, right) => {
    const dateDiff = Date.parse(right.createdAt) - Date.parse(left.createdAt)
    if (dateDiff !== 0) return dateDiff
    const attemptDiff = right.attempt - left.attempt
    if (attemptDiff !== 0) return attemptDiff
    return right.id - left.id
  })[0] || null
}

function matchingOpenIncident(manifest, check, observation) {
  return manifest.incidents.find(incident => {
    if (incident.state !== 'open' || incident.checkId !== check.id) return false
    if (!observation.run) return incident.evidenceState === observation.state && incident.run === null
    return incident.run
      && incident.run.id === observation.run.id
      && incident.run.attempt === observation.run.attempt
      && incident.run.headSha === observation.run.headSha
  }) || null
}

/**
 * Find the open signed incident that owns a newer failing run, if any.
 *
 * The run must have exactly one failed job, with the signature's job name.
 * That job's only failed step must be the signature's step, and its log must
 * contain the signature text on one line. A run without fetched evidence, a
 * failed job without a log, any extra failing job or step, or a run older
 * than the incident never matches.
 */
function signatureOwner(manifest, check, observation) {
  const run = observation.run
  if (observation.state !== 'failure-current' || !run || run.conclusion !== 'failure') return null
  const incident = manifest.incidents.find(candidate => (
    candidate.state === 'open'
      && candidate.checkId === check.id
      && candidate.failureSignature
      && candidate.evidenceState === 'failure-current'
      && candidate.run
  ))
  if (!incident) return null
  if (Date.parse(run.createdAt) < Date.parse(incident.run.createdAt)) return null
  const signature = incident.failureSignature
  if (!Array.isArray(run.failedJobs) || run.failedJobs.length !== 1) return null
  const matches = run.failedJobs.every(job => (
    job
      && job.name === signature.job
      && Array.isArray(job.failedSteps)
      && job.failedSteps.length === 1
      && job.failedSteps[0] === signature.step
      && typeof job.log === 'string'
      && job.log.split(/\r?\n/).some(line => line.includes(signature.logPattern))
  ))
  return matches ? incident : null
}

function observeCheck(check, snapshot, nowMs) {
  const rawRuns = snapshot.runs && Array.isArray(snapshot.runs[check.id])
    ? snapshot.runs[check.id]
    : []
  let runs = rawRuns.map(normalizeRun).filter(run => check.events.includes(run.event))
  if (check.kind === 'required') runs = runs.filter(run => run.headSha === snapshot.headSha)
  const run = newestRun(runs)
  const supersededCancellations = run && (run.status !== 'completed' || run.conclusion !== 'cancelled')
    ? runs
      .filter(candidate => candidate.id !== run.id && candidate.conclusion === 'cancelled')
      .map(candidate => ({
        state: 'cancelled-superseded',
        run: candidate,
        successorRunId: run.id,
        successorRunAttempt: run.attempt
      }))
    : []
  const observed = state => ({ state, run, supersededCancellations })

  if (!run) {
    if (check.kind === 'required') {
      const headAgeMinutes = (nowMs - Date.parse(snapshot.headCreatedAt)) / 60000
      if (headAgeMinutes <= check.missingGraceMinutes) {
        return { state: 'pending', run: null, supersededCancellations: [] }
      }
    }
    return { state: 'missing', run: null, supersededCancellations: [] }
  }
  if (run.status !== 'completed') return observed('pending')
  if (run.conclusion === 'success') {
    if (check.kind === 'release-evidence') {
      const ageHours = (nowMs - Date.parse(run.updatedAt)) / 3600000
      if (ageHours > check.freshnessHours) return observed('stale-success')
    }
    return observed('success-current')
  }
  if (run.conclusion === 'cancelled') return observed('cancelled-no-successor')
  return observed('failure-current')
}

function reportRun(run) {
  const { failedJobs, ...rest } = run
  return {
    ...rest,
    failedJobs: failedJobs
      ? failedJobs.map(job => ({ name: job.name, failedSteps: job.failedSteps, logRead: typeof job.log === 'string' }))
      : null
  }
}

function evaluate(manifest, snapshot, nowValue) {
  const errors = []
  const nowMs = Date.parse(nowValue || snapshot.observedAt)
  if (snapshot.schema !== 'hxhx.ci-run-snapshot.v1') {
    errors.push('run snapshot schema must be hxhx.ci-run-snapshot.v1')
  }
  if (!validSha(snapshot.headSha)) errors.push('run snapshot headSha must be a full SHA')
  if (!validDate(snapshot.headCreatedAt)) errors.push('run snapshot headCreatedAt must be an ISO timestamp')
  if (!validDate(snapshot.observedAt)) errors.push('run snapshot observedAt must be an ISO timestamp')
  if (Number.isNaN(nowMs)) errors.push('evaluation time must be a valid ISO timestamp')

  const findings = []
  for (const check of manifest.checks) {
    const observation = observeCheck(check, snapshot, nowMs)
    const exactOwner = matchingOpenIncident(manifest, check, observation)
    const signedOwner = exactOwner ? null : signatureOwner(manifest, check, observation)
    const owner = exactOwner || signedOwner
    const openForCheck = manifest.incidents.filter(incident => (
      incident.state === 'open' && incident.checkId === check.id
    ))
    const needsOwner = ['failure-current', 'cancelled-no-successor', 'stale-success', 'missing']
      .includes(observation.state)

    if (needsOwner && !owner) {
      const runLabel = observation.run
        ? `run ${observation.run.id} attempt ${observation.run.attempt}`
        : 'no qualifying run'
      const evidenceNote = observation.run && observation.run.failureEvidenceError
        ? `; failure signature evidence unavailable: ${observation.run.failureEvidenceError}`
        : ''
      errors.push(`${check.name}: ${observation.state} (${runLabel}) has no matching open P0/P1 incident${evidenceNote}`)
    }
    if (observation.state === 'success-current' && openForCheck.length > 0) {
      errors.push(`${check.name}: a newer success exists; mark its open incident resolved with that successor run`)
    }
    if (needsOwner && owner && owner.evidenceState !== observation.state) {
      errors.push(`${check.name}: incident ${owner.id} must classify evidenceState as ${observation.state}`)
    }

    findings.push({
      checkId: check.id,
      workflow: check.name,
      kind: check.kind,
      state: observation.state,
      run: observation.run ? reportRun(observation.run) : null,
      supersededCancellations: observation.supersededCancellations,
      ownerIncident: owner ? owner.id : null,
      ownerBead: owner ? owner.bead : null,
      ownerMatch: exactOwner ? 'exact-run' : (signedOwner ? 'failure-signature' : null)
    })
  }

  return {
    report: {
      schema: 'hxhx.ci-evidence-ownership-report.v1',
      repository: snapshot.repository || null,
      defaultBranch: manifest.defaultBranch,
      headSha: snapshot.headSha,
      observedAt: snapshot.observedAt,
      evaluatedAt: new Date(nowMs).toISOString(),
      outcome: errors.length === 0 ? 'pass' : 'fail',
      findings,
      errors
    },
    errors
  }
}

/**
 * Read the failed jobs, failed steps, and job logs of one run attempt.
 *
 * Any read failure, including an incomplete job list, returns
 * `failedJobs: null`. The evaluator treats that as "no evidence", so the run
 * stays unowned.
 */
async function collectFailedJobs(apiRoot, run, token, readers = {}) {
  const json = readers.json || (url => githubJson(url, token))
  const text = readers.text || (url => githubText(url, token))
  try {
    const payload = await json(`${apiRoot}/actions/runs/${run.id}/attempts/${run.attempt}/jobs?per_page=100`)
    const jobs = Array.isArray(payload && payload.jobs) ? payload.jobs : null
    if (!jobs || payload.total_count !== jobs.length) {
      throw new Error(`incomplete job list for run ${run.id} attempt ${run.attempt}`)
    }
    const failedJobs = []
    for (const job of jobs) {
      if (['success', 'skipped', 'neutral'].includes(job.conclusion)) continue
      const steps = Array.isArray(job.steps) ? job.steps : []
      failedJobs.push({
        name: job.name,
        failedSteps: steps.filter(step => step.conclusion === 'failure').map(step => step.name),
        log: await text(`${apiRoot}/actions/jobs/${job.id}/logs`)
      })
    }
    return { failedJobs, error: null }
  } catch (error) {
    return { failedJobs: null, error: error.message }
  }
}

/**
 * Attach failed-job evidence to the run that a signed open incident could own.
 *
 * The candidate is the run that `observeCheck` selects, so the live reader and
 * the evaluator use one selection rule. Evidence is read only when that run
 * completed with a failure and is not the incident's exact recorded run.
 */
async function attachSignatureEvidence(manifest, snapshot, nowMs, collect) {
  for (const check of manifest.checks) {
    const signed = manifest.incidents.some(incident => (
      incident.state === 'open' && incident.checkId === check.id && incident.failureSignature && incident.run
    ))
    if (!signed) continue
    const observation = observeCheck(check, snapshot, nowMs)
    if (observation.state !== 'failure-current' || !observation.run
      || observation.run.conclusion !== 'failure'
      || matchingOpenIncident(manifest, check, observation)) continue
    const raw = (snapshot.runs[check.id] || []).find(run => {
      const normalized = normalizeRun(run)
      return normalized.id === observation.run.id && normalized.attempt === observation.run.attempt
    })
    if (!raw) continue
    const evidence = await collect(observation.run)
    raw.failedJobs = evidence.failedJobs
    if (evidence.error) raw.failureEvidenceError = evidence.error
  }
}

async function collectLiveSnapshot(manifest, args) {
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN
  if (!token) throw new Error('--live requires GITHUB_TOKEN or GH_TOKEN')
  if (!args.repository || !/^[^/]+\/[^/]+$/.test(args.repository)) {
    throw new Error('--live requires --repository owner/name or GITHUB_REPOSITORY')
  }
  const apiRoot = `https://api.github.com/repos/${args.repository}`
  const commitRef = args.headSha || manifest.defaultBranch
  const commit = await githubJson(`${apiRoot}/commits/${encodeURIComponent(commitRef)}`, token)
  const headSha = args.headSha || commit.sha
  const headCreatedAt = commit.commit.committer.date || commit.commit.author.date
  const runs = {}

  for (const check of manifest.checks) {
    const fileName = path.basename(check.workflow)
    const collected = []
    for (const event of check.events) {
      const query = new URLSearchParams({
        branch: manifest.defaultBranch,
        event,
        per_page: '20'
      })
      if (check.kind === 'required') query.set('head_sha', headSha)
      const payload = await githubJson(
        `${apiRoot}/actions/workflows/${encodeURIComponent(fileName)}/runs?${query}`,
        token
      )
      for (const run of payload.workflow_runs || []) collected.push(normalizeRun(run))
    }
    runs[check.id] = collected
  }

  const snapshot = {
    schema: 'hxhx.ci-run-snapshot.v1',
    repository: args.repository,
    defaultBranch: manifest.defaultBranch,
    headSha,
    headCreatedAt,
    observedAt: args.now || new Date().toISOString(),
    runs
  }
  await attachSignatureEvidence(
    manifest,
    snapshot,
    Date.parse(snapshot.observedAt),
    run => collectFailedJobs(apiRoot, run, token)
  )
  return snapshot
}

async function main() {
  let args
  try {
    args = parseArgs(process.argv.slice(2))
  } catch (error) {
    console.error(`[ci-evidence-ownership] ERROR: ${error.message}`)
    process.exit(1)
  }

  try {
    const manifest = readJson(args.manifest)
    const issues = readIssues(args.beads)
    const errors = validateManifest(manifest, issues, args.manifest)
    const snapshot = args.live
      ? await collectLiveSnapshot(manifest, args)
      : readJson(args.snapshot)
    const evaluation = evaluate(manifest, snapshot, args.now)
    errors.push(...evaluation.errors)
    evaluation.report.errors = errors
    evaluation.report.outcome = errors.length === 0 ? 'pass' : 'fail'

    if (args.jsonOut) {
      fs.mkdirSync(path.dirname(args.jsonOut), { recursive: true })
      fs.writeFileSync(args.jsonOut, `${JSON.stringify(evaluation.report, null, 2)}\n`)
    }
    if (errors.length > 0) {
      for (const error of errors) console.error(`[ci-evidence-ownership] ERROR: ${error}`)
      process.exit(1)
    }
    console.log('[ci:guards] OK: required and release-evidence CI failures have active owners')
    console.log(passMarker)
  } catch (error) {
    console.error(`[ci-evidence-ownership] ERROR: ${error.stack || error.message}`)
    process.exit(1)
  }
}

if (require.main === module) main()

module.exports = {
  attachSignatureEvidence,
  collectFailedJobs,
  collectLiveSnapshot,
  evaluate,
  normalizeRun,
  observeCheck,
  parseArgs,
  readIssues,
  signatureOwner,
  validateManifest
}
