#!/usr/bin/env node
/**
 * Validates and loads the complete Core Tests shard plan.
 *
 * `npm test` remains the human-facing aggregate and source of command order.
 * The manifest assigns every one of those commands to exactly one clean CI
 * runner so a new test cannot disappear silently or run twice.
 */

const fs = require('fs')
const path = require('path')

const SCHEMA = 'hxhx.core-test-shards.v1'
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
  invariant(manifest.assignments && typeof manifest.assignments === 'object', 'manifest assignments must be an object')

  const shardIds = new Set()
  for (const shard of manifest.shards) {
    invariant(shard && typeof shard.id === 'string' && shard.id !== '', 'every shard needs a non-empty id')
    invariant(!shardIds.has(shard.id), `duplicate shard id: ${shard.id}`)
    invariant(typeof shard.label === 'string' && shard.label !== '', `shard ${shard.id} needs a label`)
    invariant(
      Number.isFinite(shard.baselineSeconds) && shard.baselineSeconds > 0,
      `shard ${shard.id} needs a positive baselineSeconds value`
    )
    shardIds.add(shard.id)
  }

  invariant(new Set(manifest.aggregateJobs).size === manifest.aggregateJobs.length, 'aggregateJobs must not repeat jobs')
  for (const job of manifest.aggregateJobs) {
    invariant(typeof job === 'string' && job !== '', 'aggregateJobs entries must be non-empty strings')
  }

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

function loadPlan(repoRoot = process.cwd()) {
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'))
  const manifestPath = path.join(repoRoot, manifestRelativePath)
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  const aggregateCommands = parseAggregateCommands(packageJson, manifest.aggregateScript)
  const shards = validateManifest(manifest, aggregateCommands)
  return { aggregateCommands, manifest, manifestPath, shards }
}

function evaluateAggregateResults(requiredJobs, needs) {
  const failures = []
  for (const job of requiredJobs) {
    const result = needs && needs[job] && needs[job].result
    if (result !== 'success') failures.push({ job, result: result || 'missing' })
  }
  return failures
}

module.exports = {
  SCHEMA,
  evaluateAggregateResults,
  loadPlan,
  parseAggregateCommands,
  validateManifest
}
