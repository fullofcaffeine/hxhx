#!/usr/bin/env node
/**
 * Prove that a peer Reflaxe checkout interoperates with hxhx's local lease.
 *
 * This is an explicit local compatibility fixture because sibling repositories
 * are not available in an isolated CI checkout. The peer keeps ownership of its
 * implementation and tests; this script checks only the shared wire behavior.
 */

'use strict'

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn } = require('child_process')
const {
  LEASE_SCHEMA,
  acquireLease,
  readLeaseSnapshot,
  releaseLease,
} = require('../hxhx/local-heavy-run-lease.js')

function usage() {
  console.log(`Usage: node scripts/ci/cross-repository-heavy-run-lease-fixture-test.js \\
  --peer-root <reflaxe-repository>

The peer must provide scripts/ci/with-heavy-run-lease.js with the shared v1
wrapper CLI. The fixture uses only a temporary lease path.`)
}

function parseArgs(argv) {
  let peerRoot = ''
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '-h' || arg === '--help') return { help: true, peerRoot: '' }
    if (arg === '--peer-root') {
      if (index + 1 >= argv.length) throw new Error('--peer-root requires a value')
      peerRoot = path.resolve(argv[index + 1])
      index += 1
      continue
    }
    throw new Error(`unknown option: ${arg}`)
  }
  if (!peerRoot) throw new Error('--peer-root is required')
  return { help: false, peerRoot }
}

function sleep(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds))
}

async function waitFor(predicate, label) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return
    await sleep(10)
  }
  throw new Error(`timed out waiting for ${label}`)
}

function runNode(args, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, args, {
      env: { ...process.env, CI: '', ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let stdout = ''
    let stderr = ''
    child.stdout.on('data', chunk => {
      stdout += chunk.toString()
    })
    child.stderr.on('data', chunk => {
      stderr += chunk.toString()
    })
    child.once('error', reject)
    child.once('close', code => resolve({ code, stdout, stderr }))
  })
}

function peerArgs(peerWrapper, leasePath, label, waitSeconds, command) {
  return [
    peerWrapper,
    '--wait-seconds',
    String(waitSeconds),
    '--poll-seconds',
    '0.01',
    '--lease-file',
    leasePath,
    '--label',
    label,
    '--repository',
    'peer-reflaxe-fixture',
    '--',
    ...command,
  ]
}

async function main() {
  const options = parseArgs(process.argv.slice(2))
  if (options.help) {
    usage()
    return
  }

  const peerWrapper = path.join(options.peerRoot, 'scripts/ci/with-heavy-run-lease.js')
  if (!fs.existsSync(peerWrapper)) {
    throw new Error(`peer wrapper is missing: ${peerWrapper}`)
  }

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-cross-repository-heavy-lease-'))
  const leasePath = path.join(temp, 'shared.lease.json')
  try {
    const peerOwner = runNode(
      peerArgs(peerWrapper, leasePath, 'peer-owns', 1, [
        process.execPath,
        '-e',
        'setTimeout(() => {}, 350)',
      ])
    )
    await waitFor(() => readLeaseSnapshot(leasePath).status === 'read', 'peer lease acquisition')

    const peerRecord = readLeaseSnapshot(leasePath).record
    assert.strictEqual(peerRecord.schema, LEASE_SCHEMA)
    assert.strictEqual(peerRecord.owner.repository, 'peer-reflaxe-fixture')
    const hxhxBlocked = acquireLease({
      leasePath,
      ownerPid: process.pid,
      label: 'hxhx-contender',
      repository: 'hxhx-fixture',
      token: '1'.repeat(32),
    })
    assert.strictEqual(hxhxBlocked.status, 'busy')
    assert.strictEqual(hxhxBlocked.inspection.record.owner.repository, 'peer-reflaxe-fixture')
    assert.strictEqual((await peerOwner).code, 0)
    assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing')
    console.log('CROSS_REPOSITORY_HEAVY_RUN_LEASE:PEER_BLOCKS_HXHX:PASS')

    const hxhxOwner = acquireLease({
      leasePath,
      ownerPid: process.pid,
      label: 'hxhx-owns',
      repository: 'hxhx-fixture',
      token: '2'.repeat(32),
    })
    assert.strictEqual(hxhxOwner.status, 'acquired')

    const peerBlocked = await runNode(
      peerArgs(peerWrapper, leasePath, 'peer-contender', 0.04, [
        process.execPath,
        '-e',
        'process.exit(99)',
      ])
    )
    assert.strictEqual(peerBlocked.code, 75, peerBlocked.stderr)
    assert.match(peerBlocked.stdout, /HAXE_FAMILY_HEAVY_RUN:WAITING/)
    assert.strictEqual(readLeaseSnapshot(leasePath).record.owner.repository, 'hxhx-fixture')
    console.log('CROSS_REPOSITORY_HEAVY_RUN_LEASE:HXHX_BLOCKS_PEER:PASS')

    const nested = await runNode(
      peerArgs(peerWrapper, leasePath, 'peer-nested', 0.1, [
        process.execPath,
        '-e',
        'process.stdout.write("NESTED_PEER_COMMAND:PASS\\n")',
      ]),
      { HXHX_HEAVY_RUN_LEASE_OWNER_PID: String(process.pid) }
    )
    assert.strictEqual(nested.code, 0, nested.stderr)
    assert.match(nested.stdout, /HAXE_FAMILY_HEAVY_RUN:REENTRANT/)
    assert.match(nested.stdout, /NESTED_PEER_COMMAND:PASS/)
    assert.strictEqual(readLeaseSnapshot(leasePath).record.owner.repository, 'hxhx-fixture')

    const released = releaseLease({
      leasePath,
      ownerPid: process.pid,
      ownerToken: '2'.repeat(32),
    })
    assert.strictEqual(released.status, 'released')
    console.log('CROSS_REPOSITORY_HEAVY_RUN_LEASE:NESTED_HANDOFF:PASS')
    console.log('CROSS_REPOSITORY_HEAVY_RUN_LEASE_FIXTURE:PASS')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

void main().catch(error => {
  console.error(`cross-repository-heavy-run-lease-fixture-test: ${error.message}`)
  process.exitCode = 1
})
