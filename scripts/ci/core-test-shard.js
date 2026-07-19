#!/usr/bin/env node
/** Runs one validated Core Tests shard in canonical `npm test` order. */

const childProcess = require('child_process')
const { loadPlan } = require('./core-test-shards')

function fail(message) {
  console.error(`[core-test-shard] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  let listOnly = false
  let shardId = null
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index]
    if (arg === '--list') {
      listOnly = true
    } else if (arg === '--shard') {
      shardId = argv[++index]
      if (!shardId) fail('--shard requires an id')
    } else {
      fail(`unknown argument: ${arg}`)
    }
  }
  if (!shardId) fail('usage: core-test-shard.js --shard <id> [--list]')
  return { listOnly, shardId }
}

function main() {
  const { listOnly, shardId } = parseArgs(process.argv.slice(2))
  let plan
  try {
    plan = loadPlan()
  } catch (error) {
    fail(error.message)
  }
  const shard = plan.shards.find(candidate => candidate.id === shardId)
  if (!shard) fail(`unknown shard ${shardId}; expected one of ${plan.shards.map(candidate => candidate.id).join(', ')}`)
  if (shard.commands.length === 0) fail(`shard ${shardId} has no commands`)

  if (listOnly) {
    for (const command of shard.commands) console.log(command)
    return
  }

  const shardStartedAt = Date.now()
  console.log(`[core-test-shard] START shard=${shard.id} commands=${shard.commands.length}`)
  for (let index = 0; index < shard.commands.length; index++) {
    const command = shard.commands[index]
    const commandStartedAt = Date.now()
    console.log(`[core-test-shard] COMMAND ${index + 1}/${shard.commands.length} START ${command}`)
    const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm'
    const result = childProcess.spawnSync(npm, ['run', command], {
      cwd: process.cwd(),
      env: process.env,
      stdio: 'inherit'
    })
    const elapsedSeconds = ((Date.now() - commandStartedAt) / 1000).toFixed(3)
    if (result.error) fail(`${command} could not start: ${result.error.message}`)
    if (result.status !== 0) {
      fail(`${command} failed with ${result.signal ? `signal ${result.signal}` : `exit ${result.status}`} after ${elapsedSeconds}s`)
    }
    console.log(`[core-test-shard] COMMAND ${index + 1}/${shard.commands.length} PASS ${command} elapsed=${elapsedSeconds}s`)
  }
  console.log(`[core-test-shard] PASS shard=${shard.id} elapsed=${((Date.now() - shardStartedAt) / 1000).toFixed(3)}s`)
}

main()
