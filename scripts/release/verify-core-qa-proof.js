#!/usr/bin/env node
/**
 * Verifies that semantic publication is backed by the exact Core QA run.
 *
 * A green workflow label is not enough: this verifier binds the candidate,
 * release-range inventory, routing policy, required QA tier, workflow run, and
 * run attempt before semantic-release is allowed to publish.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { buildInventory } = require('../ci/qa-risk-change-inventory')
const { classify, loadPolicy, normalizeChangedPath } = require('../ci/qa-risk-classifier')

const CORE_WORKFLOW = 'CI / Core PR Checks'
const PUBLISH_BRANCHES = ['main', 'master']
const RECEIPT_SCHEMA = 'hxhx.qa-risk-classification.v3'

function invariant(condition, message) {
  if (!condition) throw new Error(message)
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    throw new Error(`cannot read ${label}: ${error.message}`)
  }
}

function readPaths(filePath) {
  return [...new Set(fs.readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .map(normalizeChangedPath)
    .filter(Boolean))].sort()
}

function pathDigest(paths) {
  const rendered = paths.length === 0 ? '' : `${paths.join('\n')}\n`
  return crypto.createHash('sha256').update(rendered).digest('hex')
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right)
}

function validateRun(run, receipt, candidateSha, expectedRunAttempt) {
  invariant(run && typeof run === 'object', 'Core run metadata must be an object')
  invariant(run.name === CORE_WORKFLOW, `unexpected Core workflow: ${run.name}`)
  invariant(run.path === '.github/workflows/ci.yml', `unexpected Core workflow path: ${run.path}`)
  invariant(run.conclusion === 'success', `Core run conclusion must be success, received ${run.conclusion}`)
  invariant(['push', 'workflow_dispatch'].includes(run.event), `Core release proof cannot use event ${run.event}`)
  invariant(PUBLISH_BRANCHES.includes(run.head_branch), `Core release proof cannot use branch ${run.head_branch}`)
  invariant(run.head_sha === candidateSha, 'Core run head does not match the release candidate')
  invariant(run.event === receipt.event, 'Core run event does not match the routing receipt')
  invariant(Number(run.run_attempt) === expectedRunAttempt, 'Core run attempt does not match the selected proof attempt')

  const repository = run.repository && run.repository.full_name
  invariant(repository === receipt.source.repository, 'Core run repository does not match the routing receipt')
  invariant(Number.isInteger(receipt.source.runId) && receipt.source.runId > 0, 'routing receipt has an invalid Core run ID')
  invariant(
    Number.isInteger(receipt.source.runAttempt) && receipt.source.runAttempt > 0,
    'routing receipt has an invalid Core run attempt'
  )
  invariant(Number(run.id) === receipt.source.runId, 'Core run ID does not match the routing receipt')
  invariant(
    receipt.source.runAttempt <= expectedRunAttempt,
    'routing receipt was produced after the selected Core run attempt'
  )
  invariant(receipt.source.workflow === CORE_WORKFLOW, 'routing receipt names the wrong Core workflow')
}

function validateJobs(payload, receipt, candidateSha, expectedRunAttempt) {
  invariant(payload && Array.isArray(payload.jobs), 'Core jobs metadata must contain a jobs array')
  const aggregates = payload.jobs.filter(job => job && job.name === 'Tests')
  invariant(aggregates.length === 1, `expected exactly one Core Tests aggregate, received ${aggregates.length}`)
  const aggregate = aggregates[0]
  invariant(aggregate.status === 'completed', `Core Tests aggregate status must be completed, received ${aggregate.status}`)
  invariant(aggregate.conclusion === 'success', `Core Tests aggregate conclusion must be success, received ${aggregate.conclusion}`)
  invariant(Number(aggregate.run_id) === receipt.source.runId, 'Core Tests aggregate belongs to a different run')
  invariant(Number(aggregate.run_attempt) === expectedRunAttempt, 'Core Tests aggregate belongs to a different run attempt')
  invariant(aggregate.head_sha === candidateSha, 'Core Tests aggregate belongs to a different candidate')
  invariant(aggregate.workflow_name === CORE_WORKFLOW, 'Core Tests aggregate names the wrong workflow')
}

function validateProof(options) {
  const repositoryRoot = path.resolve(options.repositoryRoot || '.')
  const policyPath = options.policyPath || path.join(repositoryRoot, 'scripts/ci/qa-risk-policy.json')
  const candidateSha = String(options.candidateSha || '').trim().toLowerCase()
  const expectedRunAttempt = Number(options.expectedRunAttempt)
  invariant(/^[0-9a-f]{40}$/.test(candidateSha), 'candidate SHA must contain 40 hexadecimal characters')
  invariant(Number.isInteger(expectedRunAttempt) && expectedRunAttempt > 0, 'expected Core run attempt must be a positive integer')

  const receipt = options.receipt || readJson(options.receiptPath, 'Core routing receipt')
  const inventory = options.inventory || readJson(options.inventoryPath, 'Core change inventory')
  const run = options.run || readJson(options.runPath, 'Core workflow run metadata')
  const jobs = options.jobs || readJson(options.jobsPath, 'Core workflow jobs metadata')
  const changedPaths = options.changedPaths || readPaths(options.pathsPath)

  invariant(receipt.schema === RECEIPT_SCHEMA, `unexpected routing receipt schema: ${receipt.schema}`)
  invariant(receipt.producerSha === candidateSha, 'routing receipt belongs to a different candidate')
  invariant(receipt.inventory && sameJson(receipt.inventory, inventory), 'routing receipt and inventory artifact disagree')
  invariant(receipt.source && typeof receipt.source === 'object', 'routing receipt has no workflow source identity')
  invariant(inventory.complete === true, 'release-candidate change inventory is incomplete')
  invariant(inventory.headSha === candidateSha, 'change inventory belongs to a different candidate')
  invariant(inventory.changedPathCount === changedPaths.length, 'change inventory count does not match changed-files.txt')
  invariant(inventory.changedPathsSha256 === pathDigest(changedPaths), 'change inventory digest does not match changed-files.txt')

  validateRun(run, receipt, candidateSha, expectedRunAttempt)
  validateJobs(jobs, receipt, candidateSha, expectedRunAttempt)

  const recomputedInventory = buildInventory({
    repositoryRoot,
    event: receipt.event,
    eventBaseSha: inventory.eventBaseSha || '',
    headSha: candidateSha
  })
  invariant(sameJson(recomputedInventory.metadata, inventory), 'release checkout recomputed a different change inventory')
  invariant(sameJson(recomputedInventory.paths, changedPaths), 'release checkout recomputed different changed paths')

  const recomputedReceipt = classify({
    event: receipt.event,
    requestedTier: receipt.requestedTier,
    changedPaths,
    producerSha: candidateSha
  }, loadPolicy(policyPath))
  for (const field of [
    'schema',
    'policySchema',
    'policySha256',
    'producerSha',
    'event',
    'requestedTier',
    'tier',
    'changedPathCount',
    'changedPaths',
    'matches',
    'semanticOwners',
    'productSurfaces',
    'unknownPaths',
    'runs',
    'reasons'
  ]) {
    invariant(sameJson(receipt[field], recomputedReceipt[field]), `routing receipt field ${field} does not match release-side policy`)
  }

  return { receipt, inventory, run, jobs, changedPaths }
}

function parseArgs(argv) {
  const options = {}
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    const next = () => {
      index += 1
      invariant(index < argv.length, `${argument} requires a value`)
      return argv[index]
    }
    if (argument === '--receipt') options.receiptPath = next()
    else if (argument === '--inventory') options.inventoryPath = next()
    else if (argument === '--paths') options.pathsPath = next()
    else if (argument === '--run-json') options.runPath = next()
    else if (argument === '--jobs-json') options.jobsPath = next()
    else if (argument === '--candidate-sha') options.candidateSha = next()
    else if (argument === '--expected-run-attempt') options.expectedRunAttempt = next()
    else if (argument === '--repository-root') options.repositoryRoot = next()
    else if (argument === '--policy') options.policyPath = next()
    else throw new Error(`unknown argument: ${argument}`)
  }
  for (const field of ['receiptPath', 'inventoryPath', 'pathsPath', 'runPath', 'jobsPath', 'candidateSha', 'expectedRunAttempt']) {
    invariant(options[field], `missing required ${field}`)
  }
  return options
}

function main() {
  const result = validateProof(parseArgs(process.argv.slice(2)))
  console.log(
    `CORE_QA_RELEASE_PROOF:PASS candidate=${result.receipt.producerSha} tier=${result.receipt.tier} run=${result.receipt.source.runId} attempt=${result.run.run_attempt} route_attempt=${result.receipt.source.runAttempt}`
  )
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[verify-core-qa-proof] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  CORE_WORKFLOW,
  PUBLISH_BRANCHES,
  RECEIPT_SCHEMA,
  pathDigest,
  readJson,
  readPaths,
  validateJobs,
  validateProof,
  validateRun
}
