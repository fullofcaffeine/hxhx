#!/usr/bin/env node
/** Verify safe cooperative lease acquisition, recovery, heartbeat, and release. */

'use strict'

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawn, spawnSync } = require('child_process')
const {
  LEASE_SCHEMA,
  acquireLease,
  inspectLease,
  readLeaseSnapshot,
  releaseLease,
  touchLease,
} = require('../hxhx/local-heavy-run-lease.js')

const owner = { status: 'found', pid: 4101, startedAt: 'Sat Jul 18 12:00:00 2026' }
const competitor = { status: 'found', pid: 4102, startedAt: 'Sat Jul 18 12:00:01 2026' }

function identities(entries) {
  return pid => entries.get(pid) || { status: 'missing' }
}

function acquire(leasePath, identityMap, overrides = {}) {
  return acquireLease({
    leasePath,
    ownerPid: overrides.ownerPid || owner.pid,
    label: overrides.label || 'fixture-gate',
    repository: overrides.repository || 'fixture-repository',
    nowMs: overrides.nowMs || Date.parse('2026-07-18T18:00:00.000Z'),
    lookupIdentity: identities(identityMap),
    token: overrides.token || 'a'.repeat(32),
    staleAfterMs: 1_000,
  })
}

function sleepSync(milliseconds) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, milliseconds)
}

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-heavy-lease-fixture-'))
const leasePath = path.join(temp, 'shared.lease.json')
const capacityScript = path.resolve(__dirname, '../hxhx/check-local-capacity.js')

try {
  const active = new Map([
    [owner.pid, owner],
    [competitor.pid, competitor],
  ])
  const first = acquire(leasePath, active)
  assert.strictEqual(first.status, 'acquired')
  assert.strictEqual(readLeaseSnapshot(leasePath).record.schema, LEASE_SCHEMA)

  const reentrant = acquire(leasePath, active, { token: 'b'.repeat(32) })
  assert.strictEqual(reentrant.status, 'reentrant')
  assert.strictEqual(reentrant.record.owner.token, 'a'.repeat(32))

  const blocked = acquire(leasePath, active, {
    ownerPid: competitor.pid,
    token: 'b'.repeat(32),
  })
  assert.strictEqual(blocked.status, 'busy')
  assert.strictEqual(blocked.inspection.reason, 'owner_active')

  const notOwned = releaseLease({
    leasePath,
    ownerPid: competitor.pid,
    lookupIdentity: identities(active),
  })
  assert.strictEqual(notOwned.status, 'not_owned')
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'read')

  const heartbeatBefore = fs.statSync(leasePath).mtimeMs
  assert.strictEqual(touchLease({ leasePath, ownerToken: 'a'.repeat(32), nowMs: heartbeatBefore + 500 }), true)
  assert.ok(fs.statSync(leasePath).mtimeMs >= heartbeatBefore + 499)

  const released = releaseLease({ leasePath, ownerPid: owner.pid, lookupIdentity: identities(active) })
  assert.strictEqual(released.status, 'released')
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'missing')

  acquire(leasePath, active)
  const ownerGone = new Map([[competitor.pid, competitor]])
  const recoveredMissing = acquire(leasePath, ownerGone, {
    ownerPid: competitor.pid,
    token: 'c'.repeat(32),
  })
  assert.strictEqual(recoveredMissing.status, 'acquired')
  assert.strictEqual(recoveredMissing.recoveredReason, 'owner_missing')
  releaseLease({ leasePath, ownerPid: competitor.pid, ownerToken: 'c'.repeat(32) })

  acquire(leasePath, active)
  const reused = new Map([
    [owner.pid, { ...owner, startedAt: 'Sat Jul 18 12:10:00 2026' }],
    [competitor.pid, competitor],
  ])
  const recoveredReuse = acquire(leasePath, reused, {
    ownerPid: competitor.pid,
    token: 'd'.repeat(32),
  })
  assert.strictEqual(recoveredReuse.status, 'acquired')
  assert.strictEqual(recoveredReuse.recoveredReason, 'owner_pid_reused')
  releaseLease({ leasePath, ownerPid: competitor.pid, ownerToken: 'd'.repeat(32) })

  fs.writeFileSync(leasePath, '{')
  const recentMalformed = inspectLease(leasePath, {
    nowMs: fs.statSync(leasePath).mtimeMs + 100,
    staleAfterMs: 1_000,
    lookupIdentity: identities(active),
  })
  assert.strictEqual(recentMalformed.status, 'busy')
  assert.strictEqual(recentMalformed.reason, 'lease_initializing')
  const old = new Date(Date.now() - 5_000)
  fs.utimesSync(leasePath, old, old)
  const recoveredMalformed = acquire(leasePath, active, { token: 'e'.repeat(32), nowMs: Date.now() })
  assert.strictEqual(recoveredMalformed.status, 'acquired')
  assert.strictEqual(recoveredMalformed.recoveredReason, 'malformed_expired')
  releaseLease({ leasePath, ownerPid: owner.pid, ownerToken: 'e'.repeat(32) })

  fs.writeFileSync(leasePath, `${JSON.stringify({ schema: 'future.lease.v9' })}\n`)
  const mismatch = acquire(leasePath, active, { token: 'f'.repeat(32) })
  assert.strictEqual(mismatch.status, 'incompatible')
  assert.strictEqual(mismatch.inspection.reason, 'schema_mismatch')
  assert.strictEqual(readLeaseSnapshot(leasePath).status, 'read')

  fs.unlinkSync(leasePath)
  const idleFixture = path.join(temp, 'idle.json')
  const cliLease = path.join(temp, 'cli.lease.json')
  fs.writeFileSync(
    idleFixture,
    `${JSON.stringify({ cpuCount: 8, loadavg: [1, 1, 1], ci: false, processes: [] })}\n`
  )
  const admitted = spawnSync(
    process.execPath,
    [
      capacityScript,
      '--policy',
      'require',
      '--wait-seconds',
      '1',
      '--poll-seconds',
      '0.01',
      '--fixture',
      idleFixture,
      '--lease-owner-pid',
      String(process.pid),
      '--lease-file',
      cliLease,
      '--label',
      'fixture-cli',
    ],
    { encoding: 'utf8' }
  )
  assert.strictEqual(admitted.status, 0, admitted.stderr)
  assert.match(admitted.stdout, /HXHX_LOCAL_CAPACITY:PASS/)
  assert.match(admitted.stdout, /queue=admitted_immediately/)
  assert.strictEqual(readLeaseSnapshot(cliLease).status, 'read')

  const cliRelease = spawnSync(
    process.execPath,
    [
      capacityScript,
      '--release-lease',
      '--lease-owner-pid',
      String(process.pid),
      '--lease-file',
      cliLease,
    ],
    { encoding: 'utf8' }
  )
  assert.strictEqual(cliRelease.status, 0, cliRelease.stderr)
  assert.match(cliRelease.stdout, /HXHX_LOCAL_CAPACITY:LEASE_RELEASED/)
  assert.strictEqual(readLeaseSnapshot(cliLease).status, 'missing')

  const ciFixture = path.join(temp, 'ci.json')
  const ciLease = path.join(temp, 'ci.lease.json')
  fs.writeFileSync(
    ciFixture,
    `${JSON.stringify({ cpuCount: 8, loadavg: [1, 1, 1], ci: true, processes: [] })}\n`
  )
  const ci = spawnSync(
    process.execPath,
    [
      capacityScript,
      '--policy',
      'require',
      '--wait-seconds',
      '1',
      '--fixture',
      ciFixture,
      '--lease-owner-pid',
      String(process.pid),
      '--lease-file',
      ciLease,
    ],
    { encoding: 'utf8' }
  )
  assert.strictEqual(ci.status, 0, ci.stderr)
  assert.strictEqual(readLeaseSnapshot(ciLease).status, 'missing')

  const competingLease = path.join(temp, 'competing.lease.json')
  const competingOwner = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
    stdio: 'ignore',
  })
  try {
    const competing = acquireLease({
      leasePath: competingLease,
      ownerPid: competingOwner.pid,
      label: 'other-repository-gate',
      repository: 'other-repository',
      token: '9'.repeat(32),
    })
    assert.strictEqual(competing.status, 'acquired')

    const timedOut = spawnSync(
      process.execPath,
      [
        capacityScript,
        '--policy',
        'require',
        '--wait-seconds',
        '0.03',
        '--poll-seconds',
        '0.01',
        '--fixture',
        idleFixture,
        '--lease-owner-pid',
        String(process.pid),
        '--lease-file',
        competingLease,
        '--label',
        'waiting-repository-gate',
      ],
      { encoding: 'utf8' }
    )
    assert.strictEqual(timedOut.status, 75, timedOut.stderr)
    assert.strictEqual((timedOut.stdout.match(/HXHX_LOCAL_CAPACITY:WAITING/g) || []).length, 1)
    assert.match(timedOut.stdout, /observations=cooperative_lease/)
    assert.match(timedOut.stdout, /HXHX_LOCAL_CAPACITY:BLOCKED/)
    assert.match(timedOut.stdout, /queue=timed_out/)
    process.kill(competingOwner.pid, 0)
    assert.strictEqual(readLeaseSnapshot(competingLease).record.owner.pid, competingOwner.pid)
    releaseLease({ leasePath: competingLease, ownerPid: competingOwner.pid, ownerToken: '9'.repeat(32) })
  } finally {
    competingOwner.kill('SIGTERM')
  }

  const abandonedLease = path.join(temp, 'abandoned.lease.json')
  const orphanLaunch = spawnSync(
    'sh',
    ['-c', '"$1" -e \'setInterval(() => {}, 1000)\' </dev/null >/dev/null 2>&1 & echo $!', 'sh', process.execPath],
    { encoding: 'utf8' }
  )
  assert.strictEqual(orphanLaunch.status, 0, orphanLaunch.stderr)
  const abandonedOwnerPid = Number(orphanLaunch.stdout.trim())
  assert.ok(Number.isInteger(abandonedOwnerPid) && abandonedOwnerPid > 0)
  const abandonedAdmission = spawnSync(
    process.execPath,
    [
      capacityScript,
      '--policy',
      'require',
      '--wait-seconds',
      '1',
      '--fixture',
      idleFixture,
      '--lease-owner-pid',
      String(abandonedOwnerPid),
      '--lease-file',
      abandonedLease,
      '--label',
      'abandoned-owner-gate',
    ],
    { encoding: 'utf8', env: { ...process.env, HXHX_HEAVY_RUN_LEASE_HEARTBEAT_MS: '20' } }
  )
  assert.strictEqual(abandonedAdmission.status, 0, abandonedAdmission.stderr)
  assert.strictEqual(readLeaseSnapshot(abandonedLease).status, 'read')
  process.kill(abandonedOwnerPid, 'SIGKILL')
  for (let attempt = 0; attempt < 50 && readLeaseSnapshot(abandonedLease).status !== 'missing'; attempt += 1) {
    sleepSync(20)
  }
  assert.strictEqual(readLeaseSnapshot(abandonedLease).status, 'missing')

  console.log('LOCAL_HEAVY_RUN_LEASE_FIXTURE:PASS')
} finally {
  fs.rmSync(temp, { recursive: true, force: true })
}
