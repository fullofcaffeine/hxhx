#!/usr/bin/env node
/** Verify bounded capacity waiting without sampling or sleeping on the host. */

'use strict'

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
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

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-capacity-queue-cli-'))
  try {
    const fixturePath = path.join(temp, 'sequence.json')
    const reportPath = path.join(temp, 'report.json')
    fs.writeFileSync(
      fixturePath,
      `${JSON.stringify({
        cpuCount: 8,
        ci: false,
        samples: [
          { loadavg: [20, 18, 10], processes: [] },
          { loadavg: [18, 16, 10], processes: [] },
          { loadavg: [2, 1.5, 1], processes: [] },
        ],
      })}\n`
    )
    const script = path.resolve(__dirname, '../hxhx/check-local-capacity.js')
    const cli = spawnSync(
      process.execPath,
      [
        script,
        '--policy',
        'require',
        '--wait-seconds',
        '0.1',
        '--poll-seconds',
        '0.01',
        '--fixture',
        fixturePath,
        '--json-out',
        reportPath,
      ],
      { encoding: 'utf8' }
    )
    assert.strictEqual(cli.status, 0, cli.stderr)
    assert.strictEqual((cli.stdout.match(/HXHX_LOCAL_CAPACITY:WAITING/g) || []).length, 1)
    assert.match(cli.stdout, /HXHX_LOCAL_CAPACITY:PASS/)
    assert.match(cli.stdout, /queue=admitted_after_wait/)
    const cliReport = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
    assert.strictEqual(cliReport.queue.outcome, 'admitted_after_wait')
    assert.strictEqual(cliReport.queue.samples, 3)
    assert.ok(cliReport.queue.waitedMs >= 20)
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }

  console.log('LOCAL_CAPACITY_QUEUE_FIXTURE:PASS')
}

void main()
