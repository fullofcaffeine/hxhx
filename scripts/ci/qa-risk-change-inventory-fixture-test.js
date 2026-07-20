#!/usr/bin/env node
/** Focused Git-history fixtures for cumulative release-candidate QA risk. */

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { classify, loadPolicy } = require('./qa-risk-classifier')
const { buildInventory } = require('./qa-risk-change-inventory')

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

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-qa-inventory-'))
const shallowRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-qa-inventory-shallow-'))
try {
  git(root, 'init', '-q')
  git(root, 'config', 'user.name', 'QA fixture')
  git(root, 'config', 'user.email', 'qa-fixture@example.invalid')

  write(root, 'README.md', 'released\n')
  write(root, 'package.json', '{"version":"1.2.3"}\n')
  const released = commit(root, 'chore(release): 1.2.3 [skip ci]')
  git(root, 'tag', 'v1.2.3')

  write(root, 'packages/reflaxe.ocaml/src/reflaxe/ocaml/runtimegen/Runtime.hx', 'high risk\n')
  const highRisk = commit(root, 'high-risk runtime change')
  write(root, 'docs/follow-up.md', 'cheap follow-up\n')
  const cheapFollowUp = commit(root, 'docs follow-up')

  const cumulative = buildInventory({
    repositoryRoot: root,
    event: 'push',
    eventBaseSha: highRisk,
    headSha: cheapFollowUp
  })
  assert.deepStrictEqual(cumulative.metadata.base, {
    kind: 'release_tag',
    sha: released,
    tag: 'v1.2.3'
  })
  assert.deepStrictEqual(cumulative.paths, [
    'docs/follow-up.md',
    'packages/reflaxe.ocaml/src/reflaxe/ocaml/runtimegen/Runtime.hx'
  ])
  const cumulativeRisk = classify({
    event: 'push',
    changedPaths: cumulative.paths,
    producerSha: cheapFollowUp
  }, loadPolicy(path.resolve(__dirname, 'qa-risk-policy.json')))
  assert.strictEqual(cumulativeRisk.tier, 'Q3')

  const pullRequest = buildInventory({
    repositoryRoot: root,
    event: 'pull_request',
    eventBaseSha: highRisk,
    headSha: cheapFollowUp
  })
  assert.strictEqual(pullRequest.metadata.base.kind, 'pull_request_merge_base')
  assert.deepStrictEqual(pullRequest.paths, ['docs/follow-up.md'])

  write(root, 'package.json', '{"version":"1.2.4"}\n')
  const nextRelease = commit(root, 'chore(release): 1.2.4 [skip ci]')
  git(root, 'tag', 'v1.2.4')
  write(root, 'docs/after-release.md', 'new release range\n')
  const afterRelease = commit(root, 'docs after release')
  git(root, 'tag', 'v9.9.9')
  const freshRange = buildInventory({
    repositoryRoot: root,
    event: 'push',
    eventBaseSha: cheapFollowUp,
    headSha: afterRelease
  })
  assert.strictEqual(freshRange.metadata.base.tag, 'v1.2.4')
  assert.strictEqual(freshRange.metadata.base.sha, nextRelease)
  assert.deepStrictEqual(freshRange.paths, ['docs/after-release.md'])
  const freshRangeRisk = classify({
    event: 'push',
    changedPaths: freshRange.paths,
    producerSha: afterRelease
  }, loadPolicy(path.resolve(__dirname, 'qa-risk-policy.json')))
  assert.strictEqual(freshRangeRisk.tier, 'Q0')

  write(root, 'examples/focused/Main.hx', 'class Main {}\n')
  const standaloneFollowUp = commit(root, 'standalone example follow-up')
  const standaloneRange = buildInventory({
    repositoryRoot: root,
    event: 'push',
    eventBaseSha: afterRelease,
    headSha: standaloneFollowUp
  })
  const standaloneRisk = classify({
    event: 'push',
    changedPaths: standaloneRange.paths,
    producerSha: standaloneFollowUp
  }, loadPolicy(path.resolve(__dirname, 'qa-risk-policy.json')))
  assert.strictEqual(standaloneRisk.tier, 'Q1')

  const unavailable = buildInventory({
    repositoryRoot: root,
    event: 'pull_request',
    eventBaseSha: 'f'.repeat(40),
    headSha: afterRelease
  })
  assert.strictEqual(unavailable.metadata.complete, false)
  assert.deepStrictEqual(unavailable.paths, [])

  git(root, 'checkout', '-q', '--orphan', 'no-release-history')
  git(root, 'rm', '-rf', '--ignore-unmatch', '.')
  write(root, 'first.txt', 'first commit without a release tag\n')
  const firstCommit = commit(root, 'unreleased root')
  const rootInventory = buildInventory({
    repositoryRoot: root,
    event: 'push',
    eventBaseSha: '0'.repeat(40),
    headSha: firstCommit
  })
  assert.strictEqual(rootInventory.metadata.base.kind, 'repository_history')
  assert.deepStrictEqual(rootInventory.paths, ['first.txt'])

  const missingPushHistory = buildInventory({
    repositoryRoot: root,
    event: 'push',
    eventBaseSha: 'f'.repeat(40),
    headSha: firstCommit
  })
  assert.strictEqual(missingPushHistory.metadata.complete, true)
  assert.strictEqual(missingPushHistory.metadata.base.kind, 'repository_history')
  assert.deepStrictEqual(missingPushHistory.paths, ['first.txt'])

  fs.rmSync(shallowRoot, { recursive: true, force: true })
  execFileSync('git', [
    'clone', '-q', '--depth', '1', '--no-tags', '--branch', 'no-release-history', `file://${root}`, shallowRoot
  ])
  const shallowHead = git(shallowRoot, 'rev-parse', 'HEAD')
  const shallowInventory = buildInventory({
    repositoryRoot: shallowRoot,
    event: 'push',
    eventBaseSha: '0'.repeat(40),
    headSha: shallowHead
  })
  assert.strictEqual(shallowInventory.metadata.complete, false)
  assert.strictEqual(shallowInventory.metadata.base.kind, 'unavailable_shallow_history')
  assert.deepStrictEqual(shallowInventory.paths, [])
  const shallowRisk = classify({
    event: 'push',
    changedPaths: shallowInventory.paths,
    producerSha: shallowHead
  }, loadPolicy(path.resolve(__dirname, 'qa-risk-policy.json')))
  assert.strictEqual(shallowRisk.tier, 'Q3')

  console.log('QA_RISK_CHANGE_INVENTORY_FIXTURES:PASS')
} finally {
  fs.rmSync(root, { recursive: true, force: true })
  fs.rmSync(shallowRoot, { recursive: true, force: true })
}
