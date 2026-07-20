#!/usr/bin/env node
'use strict'

const assert = require('assert')
const { buildFormatterBuckets, existingFiles, runCommandWithTimeout, runFormatterQueue } = require('../lint/hx-format-guard.js')

function fixtureFiles() {
  return [
    { path: 'HugeOne.hx', lines: 100 },
    { path: 'HugeTwo.hx', lines: 80 },
    { path: 'HugeThree.hx', lines: 70 },
    { path: 'HugeFour.hx', lines: 60 },
    ...Array.from({ length: 8 }, (_, index) => ({ path: `Ordinary${index + 1}.hx`, lines: 20 }))
  ]
}

function assertExactCoverage(files, buckets) {
  const expected = files.map(file => file.path).sort()
  const actual = buckets.flatMap(bucket => bucket.files).sort()
  assert.deepStrictEqual(actual, expected)
  assert.strictEqual(new Set(actual).size, expected.length)
}

async function measureConcurrency(buckets, jobs, delayFor = () => 5, oversizedJobs = 2) {
  let active = 0
  let maximum = 0
  let activeOversized = 0
  let maximumOversized = 0
  let activeOrdinary = 0
  let maximumOrdinary = 0
  const starts = []
  const runner = async (_root, bucket, index, total) => {
    active += 1
    maximum = Math.max(maximum, active)
    if (bucket.oversized) {
      activeOversized += 1
      maximumOversized = Math.max(maximumOversized, activeOversized)
    } else {
      activeOrdinary += 1
      maximumOrdinary = Math.max(maximumOrdinary, activeOrdinary)
    }
    starts.push(index)
    const elapsedMs = delayFor(bucket, index)
    await new Promise(resolve => setTimeout(resolve, elapsedMs))
    active -= 1
    if (bucket.oversized) activeOversized -= 1
    else activeOrdinary -= 1
    return { index, total, bucket, elapsedMs, code: 0, stdout: '', stderr: '' }
  }
  const results = await runFormatterQueue('/fixture', buckets, jobs, runner, oversizedJobs)
  return { maximum, maximumOversized, maximumOrdinary, starts, results }
}

async function assertProcessExited(pid) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    try {
      process.kill(pid, 0)
    } catch (error) {
      if (error && error.code === 'ESRCH') return
      throw error
    }
    await new Promise(resolve => setTimeout(resolve, 5))
  }
  assert.fail(`timed-out child process ${pid} is still alive`)
}

async function main() {
  const present = new Set(['/repo/Keep.hx', '/repo/Nested/AlsoKeep.hx'])
  assert.deepStrictEqual(
    existingFiles('/repo', ['Keep.hx', 'Deleted.hx', 'Nested/AlsoKeep.hx'], candidate => present.has(candidate)),
    ['Keep.hx', 'Nested/AlsoKeep.hx']
  )

  const files = fixtureFiles()
  const first = buildFormatterBuckets(files, 4)
  const second = buildFormatterBuckets(files, 4)

  assert.deepStrictEqual(first, second)
  assert.strictEqual(first.oversizedThreshold, 30)
  assert.strictEqual(first.isolatedFileCount, 4)
  assert.deepStrictEqual(
    first.buckets.slice(0, 4).map(bucket => bucket.files),
    [['HugeOne.hx'], ['HugeTwo.hx'], ['HugeThree.hx'], ['HugeFour.hx']]
  )
  assert(first.buckets.slice(0, 4).every(bucket => bucket.oversized === true))
  assert(first.buckets.slice(4).every(bucket => bucket.oversized === false))
  assertExactCoverage(files, first.buckets)

  const parallel = await measureConcurrency(first.buckets, 4, bucket => (bucket.oversized ? 12 : 4))
  assert.strictEqual(parallel.maximum, 4)
  assert.strictEqual(parallel.maximumOversized, 2)
  assert.strictEqual(parallel.maximumOrdinary, 2)
  assert(parallel.starts.indexOf(5) < parallel.starts.indexOf(3), 'ordinary work should start before the third oversized file')
  assert.deepStrictEqual(
    parallel.results.map(result => result.index),
    first.buckets.map((_bucket, index) => index + 1)
  )
  assert(parallel.results.slice(0, 4).every(result => result.worker === 1 || result.worker === 2))
  assert.deepStrictEqual([...new Set(parallel.results.slice(0, 4).map(result => result.worker))].sort(), [1, 2])
  assert(parallel.results.slice(4).some(result => result.worker > 2))

  const constrained = await measureConcurrency(first.buckets, 4, bucket => (bucket.oversized ? 12 : 4), 1)
  assert.strictEqual(constrained.maximumOversized, 1)
  assert.strictEqual(constrained.maximumOrdinary, 3)

  const ordinaryOnly = await measureConcurrency(
    Array.from({ length: 6 }, (_, index) => ({ files: [`OrdinaryBucket${index + 1}.hx`], lines: 10, oversized: false })),
    3,
    () => 5
  )
  assert.strictEqual(ordinaryOnly.maximum, 3)
  assert.strictEqual(ordinaryOnly.maximumOversized, 0)
  assert.strictEqual(ordinaryOnly.maximumOrdinary, 3)

  const serialPlan = buildFormatterBuckets(files, 1)
  assert.strictEqual(serialPlan.isolatedFileCount, 0)
  assert.strictEqual(serialPlan.buckets.length, 1)
  assert.strictEqual(serialPlan.buckets[0].oversized, false)
  assertExactCoverage(files, serialPlan.buckets)
  const serial = await measureConcurrency(first.buckets, 1)
  assert.strictEqual(serial.maximum, 1)
  assert.strictEqual(serial.maximumOversized, 1)
  assert.deepStrictEqual(serial.starts, first.buckets.map((_bucket, index) => index + 1))
  assert.deepStrictEqual([...new Set(serial.results.map(result => result.worker))], [1])

  const timedOut = await runCommandWithTimeout(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { timeoutMs: 50 })
  assert.strictEqual(timedOut.timedOut, true)
  assert.notStrictEqual(timedOut.code, 0)
  assert.strictEqual(timedOut.signal, 'SIGKILL')
  await assertProcessExited(timedOut.pid)

  console.log('HX_FORMAT_GUARD_FIXTURE:PASS')
}

main().catch(error => {
  console.error(error && error.stack ? error.stack : String(error))
  process.exit(1)
})
