#!/usr/bin/env node
/**
 * Builds the immutable changed-path inventory consumed by QA risk routing.
 *
 * Pull requests describe one proposed change and therefore use their base
 * commit. Default-branch pushes describe a potential release candidate, so
 * they retain every changed path since the latest reachable release tag. A
 * cheap follow-up commit cannot erase an earlier unreleased high-risk change.
 */

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const INVENTORY_SCHEMA = 'hxhx.qa-risk-change-inventory.v1'
const RELEASE_TAG_PATTERN = /^v[0-9]+\.[0-9]+\.[0-9]+$/
const SHA_PATTERN = /^[0-9a-f]{40}$/i

function invariant(condition, message) {
  if (!condition) throw new Error(message)
}

function normalizeSha(value) {
  return String(value || '').trim().toLowerCase()
}

function git(repositoryRoot, args, options = {}) {
  return execFileSync('git', args, {
    cwd: repositoryRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', options.quiet ? 'ignore' : 'inherit']
  }).trim()
}

function commitExists(repositoryRoot, sha) {
  if (!SHA_PATTERN.test(sha)) return false
  try {
    git(repositoryRoot, ['cat-file', '-e', `${sha}^{commit}`], { quiet: true })
    return true
  } catch (_) {
    return false
  }
}

function isAncestor(repositoryRoot, ancestor, descendant) {
  if (!commitExists(repositoryRoot, ancestor) || !commitExists(repositoryRoot, descendant)) return false
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', ancestor, descendant], {
      cwd: repositoryRoot,
      stdio: 'ignore'
    })
    return true
  } catch (_) {
    return false
  }
}

function mergeBase(repositoryRoot, left, right) {
  if (!commitExists(repositoryRoot, left) || !commitExists(repositoryRoot, right)) return null
  try {
    const result = normalizeSha(git(repositoryRoot, ['merge-base', left, right], { quiet: true }))
    return commitExists(repositoryRoot, result) ? result : null
  } catch (_) {
    return null
  }
}

function isShallowRepository(repositoryRoot) {
  try {
    return git(repositoryRoot, ['rev-parse', '--is-shallow-repository'], { quiet: true }) === 'true'
  } catch (_) {
    return true
  }
}

function releaseTagMatchesCommit(repositoryRoot, tag, sha) {
  const version = tag.slice(1)
  try {
    const subject = git(repositoryRoot, ['show', '-s', '--format=%s', sha], { quiet: true })
    if (!subject.startsWith(`chore(release): ${version} [skip ci]`)) return false
    const packageJson = JSON.parse(git(repositoryRoot, ['show', `${sha}:package.json`], { quiet: true }))
    return packageJson.version === version
  } catch (_) {
    return false
  }
}

function latestReleaseTag(repositoryRoot, headSha) {
  if (!commitExists(repositoryRoot, headSha)) return null
  const tags = git(repositoryRoot, [
    'tag', '--merged', headSha, '--list', 'v[0-9]*', '--sort=-version:refname'
  ], { quiet: true }).split(/\r?\n/).filter(Boolean)
  for (const tag of tags) {
    if (!RELEASE_TAG_PATTERN.test(tag)) continue
    const sha = normalizeSha(git(repositoryRoot, ['rev-parse', `${tag}^{commit}`], { quiet: true }))
    if (
      commitExists(repositoryRoot, sha)
      && isAncestor(repositoryRoot, sha, headSha)
      && releaseTagMatchesCommit(repositoryRoot, tag, sha)
    ) {
      return { tag, sha }
    }
  }
  return null
}

function changedPaths(repositoryRoot, baseSha, headSha) {
  return git(repositoryRoot, ['diff', '--no-renames', '--name-only', baseSha, headSha], { quiet: true })
    .split(/\r?\n/)
    .map(value => value.trim().replaceAll('\\', '/'))
    .filter(Boolean)
    .sort()
}

function historyPaths(repositoryRoot, headSha) {
  return git(repositoryRoot, [
    'log', '--format=', '--no-renames', '--name-only', headSha
  ], { quiet: true })
    .split(/\r?\n/)
    .map(value => value.trim().replaceAll('\\', '/'))
    .filter(Boolean)
    .sort()
}

function buildInventory(options) {
  const repositoryRoot = path.resolve(options.repositoryRoot || '.')
  const event = String(options.event || '').trim()
  const headSha = normalizeSha(options.headSha)
  const eventBaseSha = normalizeSha(options.eventBaseSha)
  invariant(event !== '', 'event is required')
  invariant(commitExists(repositoryRoot, headSha), `head commit is unavailable: ${headSha || '<empty>'}`)

  let base = null
  let paths = []
  let complete = true
  const pullRequestBase = event === 'pull_request' ? mergeBase(repositoryRoot, eventBaseSha, headSha) : null

  if (isShallowRepository(repositoryRoot)) {
    complete = false
    base = { kind: 'unavailable_shallow_history', sha: null, tag: null }
  } else if (event === 'push' || event === 'workflow_dispatch' || event === 'schedule') {
    const release = latestReleaseTag(repositoryRoot, headSha)
    if (release) {
      base = { kind: 'release_tag', sha: release.sha, tag: release.tag }
      paths = changedPaths(repositoryRoot, release.sha, headSha)
    } else {
      base = { kind: 'repository_history', sha: null, tag: null }
      paths = historyPaths(repositoryRoot, headSha)
    }
  } else if (pullRequestBase) {
    base = { kind: 'pull_request_merge_base', sha: pullRequestBase, tag: null }
    paths = changedPaths(repositoryRoot, pullRequestBase, headSha)
  } else if (isAncestor(repositoryRoot, eventBaseSha, headSha)) {
    base = { kind: 'event_base', sha: eventBaseSha, tag: null }
    paths = changedPaths(repositoryRoot, eventBaseSha, headSha)
  } else {
    complete = false
    base = { kind: 'unavailable', sha: null, tag: null }
  }

  paths = [...new Set(paths)].sort()
  const renderedPaths = paths.length === 0 ? '' : `${paths.join('\n')}\n`
  return {
    metadata: {
      schema: INVENTORY_SCHEMA,
      event,
      complete,
      headSha,
      eventBaseSha: SHA_PATTERN.test(eventBaseSha) ? eventBaseSha : null,
      base,
      changedPathCount: paths.length,
      changedPathsSha256: crypto.createHash('sha256').update(renderedPaths).digest('hex')
    },
    paths,
    renderedPaths
  }
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
    if (argument === '--event') options.event = next()
    else if (argument === '--event-base-sha') options.eventBaseSha = next()
    else if (argument === '--head-sha') options.headSha = next()
    else if (argument === '--repository-root') options.repositoryRoot = next()
    else if (argument === '--paths-output') options.pathsOutput = next()
    else if (argument === '--metadata-output') options.metadataOutput = next()
    else throw new Error(`unknown argument: ${argument}`)
  }
  invariant(options.pathsOutput, '--paths-output is required')
  invariant(options.metadataOutput, '--metadata-output is required')
  return options
}

function main() {
  const options = parseArgs(process.argv.slice(2))
  const inventory = buildInventory(options)
  fs.mkdirSync(path.dirname(options.pathsOutput), { recursive: true })
  fs.mkdirSync(path.dirname(options.metadataOutput), { recursive: true })
  fs.writeFileSync(options.pathsOutput, inventory.renderedPaths)
  fs.writeFileSync(options.metadataOutput, `${JSON.stringify(inventory.metadata, null, 2)}\n`)
  process.stdout.write(`${JSON.stringify(inventory.metadata, null, 2)}\n`)
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[qa-risk-change-inventory] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  INVENTORY_SCHEMA,
  RELEASE_TAG_PATTERN,
  buildInventory,
  changedPaths,
  commitExists,
  historyPaths,
  isAncestor,
  isShallowRepository,
  latestReleaseTag,
  mergeBase,
  normalizeSha,
  parseArgs,
  releaseTagMatchesCommit
}
