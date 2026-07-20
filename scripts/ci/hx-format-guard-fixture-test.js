#!/usr/bin/env node
'use strict'

const assert = require('assert')
const { buildFormatterBuckets, existingFiles, runFormatterQueue } = require('../lint/hx-format-guard.js')

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

async function measureConcurrency(buckets, jobs, delayFor = () => 5) {
  let active = 0
  let maximum = 0
  const starts = []
  const runner = async (_root, bucket, index, total) => {
    active += 1
    maximum = Math.max(maximum, active)
    starts.push(index)
    const elapsedMs = delayFor(index)
    await new Promise(resolve => setTimeout(resolve, elapsedMs))
    active -= 1
    return { index, total, bucket, elapsedMs, code: 0, stdout: '', stderr: '' }
  }
  const results = await runFormatterQueue('/fixture', buckets, jobs, runner)
  return { maximum, starts, results }
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
  assertExactCoverage(files, first.buckets)

  const parallel = await measureConcurrency(first.buckets, 2)
  assert.strictEqual(parallel.maximum, 2)
  assert.deepStrictEqual(parallel.starts, first.buckets.map((_bucket, index) => index + 1))
  assert.deepStrictEqual(
    parallel.results.map(result => result.index),
    first.buckets.map((_bucket, index) => index + 1)
  )
  assert.deepStrictEqual([...new Set(parallel.results.map(result => result.worker))].sort(), [1, 2])

  const skewed = await measureConcurrency(first.buckets, 2, index => (index === 1 ? 30 : 2))
  assert.strictEqual(skewed.results[0].worker, 1)
  assert.deepStrictEqual([...new Set(skewed.results.slice(1).map(result => result.worker))], [2])

  const serialPlan = buildFormatterBuckets(files, 1)
  assert.strictEqual(serialPlan.isolatedFileCount, 0)
  assert.strictEqual(serialPlan.buckets.length, 1)
  assertExactCoverage(files, serialPlan.buckets)
  const serial = await measureConcurrency(first.buckets, 1)
  assert.strictEqual(serial.maximum, 1)
  assert.deepStrictEqual([...new Set(serial.results.map(result => result.worker))], [1])

  console.log('HX_FORMAT_GUARD_FIXTURE:PASS')
}

main().catch(error => {
  console.error(error && error.stack ? error.stack : String(error))
  process.exit(1)
})
