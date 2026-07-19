#!/usr/bin/env node
/**
 * Bounded, request-local waiting for the heavyweight-run capacity check.
 *
 * The capacity evaluator remains a one-sample policy decision. This module
 * owns only time: it repeats that decision until the host is admitted, the
 * caller's deadline expires, or the caller cancels. Callers receive one event
 * when the blocking reason changes, rather than one line for every poll.
 */

'use strict'

class CapacityQueueCancelledError extends Error {
  constructor() {
    super('capacity wait cancelled')
    this.name = 'CapacityQueueCancelledError'
  }
}

function defaultSleep(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds))
}

function blockingSignature(report) {
  return JSON.stringify({
    observations: report.observations || [],
    policy: report.resolvedPolicy,
  })
}

/**
 * Wait for a blocked `require` decision to become admissible.
 *
 * `readReport` is deliberately injected so fixtures can advance a virtual
 * clock without sampling or sleeping on the real host.
 */
async function waitForCapacity({
  readReport,
  maxWaitMs = 0,
  pollIntervalMs = 10_000,
  now = Date.now,
  sleep = defaultSleep,
  signal,
  onWaiting = () => {},
}) {
  if (typeof readReport !== 'function') throw new Error('readReport must be a function')
  if (!Number.isFinite(maxWaitMs) || maxWaitMs < 0) throw new Error('maxWaitMs must be non-negative')
  if (!Number.isFinite(pollIntervalMs) || pollIntervalMs <= 0) {
    throw new Error('pollIntervalMs must be positive')
  }

  const startedAtMs = now()
  let samples = 0
  let lastBlockingSignature = ''

  while (true) {
    if (signal && signal.aborted) throw new CapacityQueueCancelledError()

    const report = await readReport()
    samples += 1
    const waitedMs = Math.max(0, now() - startedAtMs)

    if (report.status !== 'blocked') {
      return {
        report,
        outcome: waitedMs > 0 ? 'admitted_after_wait' : 'admitted_immediately',
        waitedMs,
        samples,
      }
    }

    if (maxWaitMs === 0) {
      return { report, outcome: 'blocked_immediately', waitedMs, samples }
    }

    const signature = blockingSignature(report)
    if (signature !== lastBlockingSignature) {
      onWaiting({ report, waitedMs, samples })
      lastBlockingSignature = signature
    }

    if (waitedMs >= maxWaitMs) {
      return { report, outcome: 'timed_out', waitedMs, samples }
    }

    const remainingMs = maxWaitMs - waitedMs
    await sleep(Math.min(pollIntervalMs, remainingMs), signal)
  }
}

module.exports = {
  CapacityQueueCancelledError,
  blockingSignature,
  waitForCapacity,
}
