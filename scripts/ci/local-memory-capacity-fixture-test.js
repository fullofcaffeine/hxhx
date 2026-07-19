#!/usr/bin/env node
/** Verify available-memory parsing and reviewed reserve calculations. */

'use strict'

const assert = require('assert')
const {
  GIB,
  assessMemoryCapacity,
  memoryThresholdBytes,
  parseLinuxAvailableMemory,
  parseMacOsAvailableMemory,
} = require('../hxhx/local-memory-capacity.js')

assert.strictEqual(
  parseMacOsAvailableMemory('System-wide memory free percentage: 42%\n', 32 * GIB),
  Math.round(13.44 * GIB)
)
assert.throws(() => parseMacOsAvailableMemory('no percentage here', 32 * GIB))
assert.strictEqual(
  parseLinuxAvailableMemory('MemTotal:       16000000 kB\nMemAvailable:    6291456 kB\n'),
  6 * GIB
)
assert.throws(() => parseLinuxAvailableMemory('MemFree: 10 kB\n'))

assert.strictEqual(memoryThresholdBytes(16 * GIB, 4, 0.1), 4 * GIB)
assert.strictEqual(memoryThresholdBytes(64 * GIB, 4, 0.1), 6.4 * GIB)

const safe = assessMemoryCapacity(
  {
    totalMemoryBytes: 32 * GIB,
    availableMemoryBytes: 8 * GIB,
    availableMemoryProvenance: 'fixture',
    availableMemoryReliable: true,
  },
  { minAvailableMemoryGiB: 4, minAvailableMemoryFraction: 0.1 }
)
assert.strictEqual(safe.status, 'safe')
assert.strictEqual(safe.thresholdGiB, 4)

const pressured = assessMemoryCapacity(
  {
    totalMemoryBytes: 64 * GIB,
    availableMemoryBytes: 6 * GIB,
    availableMemoryProvenance: 'fixture',
    availableMemoryReliable: true,
  },
  { minAvailableMemoryGiB: 4, minAvailableMemoryFraction: 0.1 }
)
assert.strictEqual(pressured.status, 'pressured')
assert.strictEqual(pressured.thresholdGiB, 6.4)

const unavailable = assessMemoryCapacity(
  {
    totalMemoryBytes: 32 * GIB,
    availableMemoryBytes: 100 * 1024 * 1024,
    availableMemoryProvenance: 'node_raw_free_fallback',
    availableMemoryReliable: false,
  },
  { minAvailableMemoryGiB: 4, minAvailableMemoryFraction: 0.1 }
)
assert.strictEqual(unavailable.status, 'unavailable')

console.log('LOCAL_MEMORY_CAPACITY_FIXTURE:PASS')
