#!/usr/bin/env node
/**
 * Validates and loads the complete Core Tests shard plan.
 *
 * `npm test` remains the human-facing aggregate and source of command order.
 * The manifest assigns every one of those commands to exactly one clean CI
 * runner so a new test cannot disappear silently or run twice. It also owns
 * the minimum QA tier for each shard and aggregate prerequisite, allowing the
 * stable Tests check to distinguish an authorized skip from missing evidence.
 */

const fs = require('fs')
const path = require('path')

const SCHEMA = 'hxhx.core-test-shards.v3'
const QA_TIERS = ['Q0', 'Q1', 'Q2', 'Q3', 'Q4']
const manifestRelativePath = 'scripts/ci/core-test-shards.json'

function invariant(condition, message) {
  if (!condition) throw new Error(message)
}

function parseAggregateCommands(packageJson, aggregateScript) {
  const script = packageJson.scripts && packageJson.scripts[aggregateScript]
  invariant(typeof script === 'string' && script.trim() !== '', `package.json is missing scripts.${aggregateScript}`)

  const commands = script.split(/\s*&&\s*/).map((part, index) => {
    const match = part.match(/^npm run\s+([A-Za-z0-9:._-]+)$/)
    invariant(
      match,
      `scripts.${aggregateScript} command ${index + 1} must be exactly "npm run <script>", got ${JSON.stringify(part)}`
    )
    return match[1]
  })
  invariant(commands.length > 0, `scripts.${aggregateScript} must contain at least one command`)
  invariant(new Set(commands).size === commands.length, `scripts.${aggregateScript} must not repeat commands`)
  return commands
}

function validateManifest(manifest, aggregateCommands) {
  invariant(manifest && manifest.schema === SCHEMA, `manifest schema must be ${SCHEMA}`)
  invariant(typeof manifest.aggregateScript === 'string', 'manifest aggregateScript must be a string')
  invariant(Array.isArray(manifest.shards) && manifest.shards.length > 0, 'manifest shards must be a non-empty array')
  invariant(Array.isArray(manifest.aggregateJobs), 'manifest aggregateJobs must be an array')
  invariant(
    manifest.aggregateJobMinimumTiers && typeof manifest.aggregateJobMinimumTiers === 'object',
    'manifest aggregateJobMinimumTiers must be an object'
  )
  invariant(manifest.assignments && typeof manifest.assignments === 'object', 'manifest assignments must be an object')

  const shardIds = new Set()
  for (const shard of manifest.shards) {
    invariant(shard && typeof shard.id === 'string' && shard.id !== '', 'every shard needs a non-empty id')
    invariant(!shardIds.has(shard.id), `duplicate shard id: ${shard.id}`)
    invariant(typeof shard.label === 'string' && shard.label !== '', `shard ${shard.id} needs a label`)
    invariant(QA_TIERS.includes(shard.minimumTier), `shard ${shard.id} needs a valid minimumTier`)
    invariant(
      QA_TIERS.indexOf(shard.minimumTier) >= QA_TIERS.indexOf('Q2'),
      `shard ${shard.id} minimumTier must be Q2 or higher`
    )
    invariant(
      Number.isFinite(shard.baselineSeconds) && shard.baselineSeconds > 0,
      `shard ${shard.id} needs a positive baselineSeconds value`
    )
    if (shard.preparation != null) {
      invariant(shard.preparation && typeof shard.preparation === 'object', `shard ${shard.id} preparation must be an object`)
      invariant(shard.preparation.kind === 'shared-macro-host', `shard ${shard.id} has an unknown preparation kind`)
      invariant(shard.id === 'macro-host-integration', 'only the macro-host-integration shard may prepare a shared macro host')
      invariant(
        shard.preparation.plan === 'scripts/ci/macro-host-integration-plan.json',
        `shard ${shard.id} shared macro-host preparation references the wrong plan`
      )
    }
    shardIds.add(shard.id)
  }

  invariant(new Set(manifest.aggregateJobs).size === manifest.aggregateJobs.length, 'aggregateJobs must not repeat jobs')
  for (const job of manifest.aggregateJobs) {
    invariant(typeof job === 'string' && job !== '', 'aggregateJobs entries must be non-empty strings')
    invariant(
      QA_TIERS.includes(manifest.aggregateJobMinimumTiers[job]),
      `aggregate job ${job} needs a valid minimum tier`
    )
  }
  const tieredJobs = Object.keys(manifest.aggregateJobMinimumTiers)
  invariant(
    tieredJobs.length === manifest.aggregateJobs.length && tieredJobs.every(job => manifest.aggregateJobs.includes(job)),
    'aggregateJobMinimumTiers must contain exactly the aggregateJobs entries'
  )

  const aggregateSet = new Set(aggregateCommands)
  const assignedCommands = Object.keys(manifest.assignments)
  for (const command of aggregateCommands) {
    invariant(
      Object.prototype.hasOwnProperty.call(manifest.assignments, command),
      `aggregate command is not assigned to a CI shard: ${command}`
    )
    invariant(
      shardIds.has(manifest.assignments[command]),
      `aggregate command ${command} references unknown shard ${manifest.assignments[command]}`
    )
  }
  for (const command of assignedCommands) {
    invariant(aggregateSet.has(command), `shard manifest contains a command not present in npm test: ${command}`)
  }
  invariant(
    assignedCommands.length === aggregateCommands.length,
    `expected ${aggregateCommands.length} assignments, found ${assignedCommands.length}`
  )

  return manifest.shards.map(shard => ({
    ...shard,
    commands: aggregateCommands.filter(command => manifest.assignments[command] === shard.id)
  }))
}

/** Returns aggregate jobs whose declared minimum tier is satisfied. */
function jobsRequiredAtTier(manifest, tier) {
  invariant(QA_TIERS.includes(tier), `QA tier must be one of ${QA_TIERS.join(', ')}`)
  const tierIndex = QA_TIERS.indexOf(tier)
  return manifest.aggregateJobs.filter(job => tierIndex >= QA_TIERS.indexOf(manifest.aggregateJobMinimumTiers[job]))
}

function loadPlan(repoRoot = process.cwd()) {
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'))
  const manifestPath = path.join(repoRoot, manifestRelativePath)
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  const aggregateCommands = parseAggregateCommands(packageJson, manifest.aggregateScript)
  const shards = validateManifest(manifest, aggregateCommands)
  return { aggregateCommands, manifest, manifestPath, shards }
}

function evaluateAggregateResults(requiredJobs, needs, options = {}) {
  const allowSkipped = new Set(options.allowSkipped || [])
  const failures = []
  for (const job of requiredJobs) {
    const result = needs && needs[job] && needs[job].result
    if (result === 'skipped' && allowSkipped.has(job)) continue
    if (result !== 'success') failures.push({ job, result: result || 'missing' })
  }
  return failures
}

module.exports = {
  QA_TIERS,
  SCHEMA,
  evaluateAggregateResults,
  jobsRequiredAtTier,
  loadPlan,
  parseAggregateCommands,
  validateManifest
}
