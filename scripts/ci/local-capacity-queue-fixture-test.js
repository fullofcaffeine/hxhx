#!/usr/bin/env node
/** Verify bounded capacity waiting without sampling or sleeping on the host. */

'use strict'

const assert = require('assert')
const {
  CapacityQueueCancelledError,
  waitForCapacity,
} = require('../hxhx/local-capacity-queue.js')

function report(status, observations = []) {
  return {
    status,
    resolvedPolicy: 'require',
    observations,
    competingCompilerProcessCount: observations.length,
  }
}

function virtualQueue(reports, overrides = {}) {
  let nowMs = 0
  let index = 0
  const transitions = []
  return waitForCapacity({
    readReport: () => reports[Math.min(index++, reports.length - 1)],
    maxWaitMs: 30_000,
    pollIntervalMs: 10_000,
    now: () => nowMs,
    sleep: async milliseconds => {
      nowMs += milliseconds
    },
    onWaiting: event => transitions.push(event.report.observations.join(',')),
    ...overrides,
  }).then(result => ({ result, transitions }))
}

async function main() {
  const immediate = await virtualQueue([report('pass')])
  assert.strictEqual(immediate.result.outcome, 'admitted_immediately')
  assert.strictEqual(immediate.result.samples, 1)
  assert.deepStrictEqual(immediate.transitions, [])

  const admitted = await virtualQueue([
    report('blocked', ['sustained_load']),
    report('blocked', ['sustained_load']),
    report('pass'),
  ])
  assert.strictEqual(admitted.result.outcome, 'admitted_after_wait')
  assert.strictEqual(admitted.result.waitedMs, 20_000)
  assert.strictEqual(admitted.result.samples, 3)
  assert.deepStrictEqual(admitted.transitions, ['sustained_load'])

  const changedReason = await virtualQueue([
    report('blocked', ['load_spike']),
    report('blocked', ['sustained_load']),
    report('pass'),
  ])
  assert.deepStrictEqual(changedReason.transitions, ['load_spike', 'sustained_load'])

  const timedOut = await virtualQueue([report('blocked', ['sustained_load'])], {
    maxWaitMs: 25_000,
  })
  assert.strictEqual(timedOut.result.outcome, 'timed_out')
  assert.strictEqual(timedOut.result.waitedMs, 25_000)
  assert.strictEqual(timedOut.result.samples, 4)
  assert.deepStrictEqual(timedOut.transitions, ['sustained_load'])

  const disabled = await virtualQueue([report('blocked', ['load_spike'])], { maxWaitMs: 0 })
  assert.strictEqual(disabled.result.outcome, 'blocked_immediately')
  assert.deepStrictEqual(disabled.transitions, [])

  const controller = new AbortController()
  await assert.rejects(
    virtualQueue([report('blocked', ['sustained_load'])], {
      signal: controller.signal,
      sleep: async () => controller.abort(),
    }),
    error => error instanceof CapacityQueueCancelledError
  )

  console.log('LOCAL_CAPACITY_QUEUE_FIXTURE:PASS')
}

void main()
