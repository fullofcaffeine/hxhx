#!/usr/bin/env node
/** Synthetic release-boundary coverage for exact Core QA proof verification. */

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { buildInventory } = require('../ci/qa-risk-change-inventory')
const { classify, loadPolicy } = require('../ci/qa-risk-classifier')
const { validateProof } = require('./verify-core-qa-proof')

function git(root, ...args) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim()
}

function write(root, file, contents) {
  const target = path.join(root, file)
  fs.mkdirSync(path.dirname(target), { recursive: true })
  fs.writeFileSync(target, contents)
}

function commit(root, message) {
  git(root, 'add', '.')
  git(root, 'commit', '-m', message)
  return git(root, 'rev-parse', 'HEAD')
}

function source() {
  return {
    repository: 'fullofcaffeine/hxhx',
    workflow: 'CI / Core PR Checks',
    runId: 12345,
    runAttempt: 2
  }
}

function run(candidateSha, overrides = {}) {
  return {
    id: 12345,
    run_attempt: 2,
    name: 'CI / Core PR Checks',
    path: '.github/workflows/ci.yml',
    event: 'push',
    head_branch: 'main',
    head_sha: candidateSha,
    conclusion: 'success',
    repository: { full_name: 'fullofcaffeine/hxhx' },
    ...overrides
  }
}

function jobs(candidateSha, overrides = {}) {
  return {
    total_count: 1,
    jobs: [{
      name: 'Tests',
      status: 'completed',
      conclusion: 'success',
      run_id: 12345,
      run_attempt: 2,
      head_sha: candidateSha,
      workflow_name: 'CI / Core PR Checks',
      ...overrides
    }]
  }
}

function expectFailure(callback, pattern) {
  assert.throws(callback, pattern)
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-release-proof-'))
try {
  git(root, 'init', '-q')
  git(root, 'config', 'user.name', 'Release proof fixture')
  git(root, 'config', 'user.email', 'release-proof@example.invalid')
  write(root, 'README.md', 'release baseline\n')
  commit(root, 'release baseline')
  git(root, 'tag', 'v1.2.3')

  write(root, 'packages/reflaxe.ocaml/src/reflaxe/ocaml/runtimegen/Runtime.hx', 'high risk\n')
  const highRisk = commit(root, 'high-risk runtime change')
  write(root, 'docs/follow-up.md', 'cheap follow-up\n')
  const candidate = commit(root, 'cheap follow-up')

  const inventory = buildInventory({
    repositoryRoot: root,
    event: 'push',
    eventBaseSha: highRisk,
    headSha: candidate
  })
  const policyPath = path.resolve(__dirname, '../ci/qa-risk-policy.json')
  const receipt = classify({
    event: 'push',
    changedPaths: inventory.paths,
    producerSha: candidate
  }, loadPolicy(policyPath))
  receipt.inventory = inventory.metadata
  receipt.source = source()

  const options = {
    repositoryRoot: root,
    policyPath,
    candidateSha: candidate,
    expectedRunAttempt: 2,
    receipt,
    inventory: inventory.metadata,
    changedPaths: inventory.paths,
    run: run(candidate),
    jobs: jobs(candidate)
  }
  const result = validateProof(options)
  assert.strictEqual(result.receipt.tier, 'Q3')

  expectFailure(() => validateProof({
    ...options,
    run: run(candidate, { run_attempt: 1 })
  }), /attempt does not match the selected proof attempt/)

  expectFailure(() => validateProof({
    ...options,
    run: run(candidate, { conclusion: 'cancelled' })
  }), /conclusion must be success/)

  expectFailure(() => validateProof({
    ...options,
    run: run(candidate, { path: '.github/workflows/lookalike.yml' })
  }), /unexpected Core workflow path/)

  expectFailure(() => validateProof({
    ...options,
    run: run(candidate, { head_branch: 'feature/unreleased' })
  }), /cannot use branch/)

  expectFailure(() => validateProof({
    ...options,
    jobs: jobs(candidate, { conclusion: 'skipped' })
  }), /aggregate conclusion must be success/)

  expectFailure(() => validateProof({
    ...options,
    jobs: { total_count: 0, jobs: [] }
  }), /expected exactly one Core Tests aggregate/)

  expectFailure(() => validateProof({
    ...options,
    jobs: jobs(candidate, { run_attempt: 1 })
  }), /aggregate belongs to a different run attempt/)

  const earlierRouteReceipt = {
    ...receipt,
    source: { ...receipt.source, runAttempt: 1 }
  }
  validateProof({ ...options, receipt: earlierRouteReceipt })
  expectFailure(() => validateProof({
    ...options,
    receipt: { ...receipt, source: { ...receipt.source, runAttempt: 3 } }
  }), /produced after the selected Core run attempt/)
  expectFailure(() => validateProof({
    ...options,
    receipt: { ...receipt, source: { ...receipt.source, runAttempt: 0 } }
  }), /invalid Core run attempt/)

  const cheapInventory = {
    ...inventory.metadata,
    base: { kind: 'event_base', sha: highRisk, tag: null },
    changedPathCount: 1,
    changedPathsSha256: require('./verify-core-qa-proof').pathDigest(['docs/follow-up.md'])
  }
  const cheapReceipt = classify({
    event: 'push',
    changedPaths: ['docs/follow-up.md'],
    producerSha: candidate
  }, loadPolicy(policyPath))
  cheapReceipt.inventory = cheapInventory
  cheapReceipt.source = source()
  expectFailure(() => validateProof({
    ...options,
    receipt: cheapReceipt,
    inventory: cheapInventory,
    changedPaths: ['docs/follow-up.md']
  }), /recomputed a different change inventory/)

  console.log('CORE_QA_RELEASE_PROOF_FIXTURES:PASS')
} finally {
  fs.rmSync(root, { recursive: true, force: true })
}
