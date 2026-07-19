#!/usr/bin/env node
/** Keep one cooperative heavy-run lease live while its owning shell exists. */

'use strict'

const {
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  lookupProcessIdentity,
  readLeaseSnapshot,
  releaseLease,
  touchLease,
} = require('./local-heavy-run-lease.js')

function sleep(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds))
}

async function main(env = process.env) {
  const leasePath = env.HXHX_HEAVY_RUN_WATCH_LEASE_FILE || ''
  const ownerPid = Number(env.HXHX_HEAVY_RUN_WATCH_OWNER_PID || 0)
  const ownerStartedAt = env.HXHX_HEAVY_RUN_WATCH_OWNER_STARTED_AT || ''
  const ownerToken = env.HXHX_HEAVY_RUN_WATCH_OWNER_TOKEN || ''
  const intervalMs = Number(env.HXHX_HEAVY_RUN_WATCH_INTERVAL_MS || DEFAULT_HEARTBEAT_INTERVAL_MS)
  if (!leasePath || !Number.isInteger(ownerPid) || ownerPid <= 0 || !ownerStartedAt || !ownerToken) return
  if (!Number.isFinite(intervalMs) || intervalMs <= 0) return

  let stopping = false
  process.once('SIGINT', () => {
    stopping = true
  })
  process.once('SIGTERM', () => {
    stopping = true
  })

  while (!stopping) {
    const snapshot = readLeaseSnapshot(leasePath)
    if (
      snapshot.status !== 'read' ||
      !snapshot.record.owner ||
      snapshot.record.owner.token !== ownerToken
    ) {
      return
    }

    const identity = lookupProcessIdentity(ownerPid)
    if (identity.status !== 'found' || identity.startedAt !== ownerStartedAt) {
      releaseLease({ leasePath, ownerPid, ownerToken })
      return
    }
    if (!touchLease({ leasePath, ownerToken })) return
    await sleep(intervalMs)
  }
}

void main()
