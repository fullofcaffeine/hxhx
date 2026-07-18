#!/usr/bin/env node
/** Verify local capacity decisions, CLI exit codes, and safe process reporting. */

'use strict'

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const {
  BLOCKED_EXIT_CODE,
  evaluateCapacity,
  parseProcessTable,
  resolvePolicy,
} = require('../hxhx/check-local-capacity.js')

const root = path.resolve(__dirname, '../..')
const script = path.join(root, 'scripts/hxhx/check-local-capacity.js')

function options(policy = 'require') {
  return {
    policy,
    label: 'fixture-heavy-run',
    maxLoadPerCpu: 1.5,
  }
}

function state(overrides = {}) {
  return {
    source: 'fixture',
    timestamp: '2026-07-18T00:00:00.000Z',
    cpuCount: 8,
    loadavg: [2, 1.5, 1],
    totalMemoryBytes: 16 * 1024 * 1024 * 1024,
    freeMemoryBytes: 8 * 1024 * 1024 * 1024,
    ci: false,
    competitors: [],
    collectionErrors: [],
    ...overrides,
  }
}

assert.strictEqual(resolvePolicy('auto', false), 'require')
assert.strictEqual(resolvePolicy('auto', true), 'warn')
assert.strictEqual(resolvePolicy('off', false), 'off')

const idle = evaluateCapacity(state(), options())
assert.strictEqual(idle.status, 'pass')
assert.strictEqual(idle.exitCode, 0)

const saturatedState = state({
  loadavg: [20, 18, 10],
  competitors: [
    { pid: 101, parentPid: 1, cpuPercent: 98, elapsed: '04:00', kind: 'haxe' },
    { pid: 102, parentPid: 1, cpuPercent: 75, elapsed: '03:00', kind: 'dune' },
  ],
})
const blocked = evaluateCapacity(saturatedState, options())
assert.strictEqual(blocked.status, 'blocked')
assert.strictEqual(blocked.exitCode, BLOCKED_EXIT_CODE)
assert.deepStrictEqual(blocked.observations, ['sustained_load', 'load_spike'])
assert.strictEqual(blocked.competingCompilerProcessCount, 2)

const warning = evaluateCapacity({ ...saturatedState, ci: true }, options('auto'))
assert.strictEqual(warning.status, 'warning')
assert.strictEqual(warning.exitCode, 0)

const disabled = evaluateCapacity(saturatedState, options('off'))
assert.strictEqual(disabled.status, 'off')
assert.strictEqual(disabled.exitCode, 0)

const spike = evaluateCapacity(state({ loadavg: [31, 4, 3] }), options())
assert.strictEqual(spike.status, 'blocked')
assert.deepStrictEqual(spike.observations, ['load_spike'])

const parsedProcesses = parseProcessTable(
  [
    '101 1 97.5 00:10 /tool/haxe --token never-report-this',
    '102 1 80.0 00:20 dune build',
    '104 1 0.0 01-00:00:00 /tool/haxe --wait 12345',
    '103 1 10.0 00:30 node scripts/hxhx/check-local-capacity.js',
  ].join('\n'),
  999,
  998
)
assert.deepStrictEqual(parsedProcesses.map(row => row.kind), ['haxe', 'dune'])
assert.ok(!JSON.stringify(parsedProcesses).includes('never-report-this'))
assert.ok(!JSON.stringify(parsedProcesses).includes('12345'))

const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-capacity-fixture-'))
try {
  const fixturePath = path.join(temp, 'saturated.json')
  const reportPath = path.join(temp, 'report.json')
  fs.writeFileSync(
    fixturePath,
    JSON.stringify({
      cpuCount: 8,
      loadavg: [20, 18, 10],
      processes: [
        {
          pid: 101,
          parentPid: 1,
          cpuPercent: 98,
          elapsed: '04:00',
          command: '/tool/haxe --token never-report-this',
        },
      ],
    })
  )

  const localEnv = { ...process.env }
  for (const name of ['CI', 'GITHUB_ACTIONS', 'BUILDKITE', 'CIRCLECI']) delete localEnv[name]
  const local = spawnSync(
    process.execPath,
    [script, '--policy', 'auto', '--fixture', fixturePath, '--json-out', reportPath],
    { cwd: root, env: localEnv, encoding: 'utf8' }
  )
  assert.strictEqual(local.status, BLOCKED_EXIT_CODE, local.stderr)
  assert.match(local.stdout, /HXHX_LOCAL_CAPACITY:BLOCKED/)
  const stored = fs.readFileSync(reportPath, 'utf8')
  assert.ok(!stored.includes('never-report-this'))
  assert.strictEqual(JSON.parse(stored).status, 'blocked')

  const ci = spawnSync(process.execPath, [script, '--policy', 'auto', '--fixture', fixturePath], {
    cwd: root,
    env: { ...localEnv, CI: '1' },
    encoding: 'utf8',
  })
  assert.strictEqual(ci.status, BLOCKED_EXIT_CODE, 'fixture ci=false must remain deterministic')

  const ciFixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'))
  ciFixture.ci = true
  fs.writeFileSync(fixturePath, JSON.stringify(ciFixture))
  const ciWarning = spawnSync(process.execPath, [script, '--policy', 'auto', '--fixture', fixturePath], {
    cwd: root,
    env: localEnv,
    encoding: 'utf8',
  })
  assert.strictEqual(ciWarning.status, 0, ciWarning.stderr)
  assert.match(ciWarning.stdout, /HXHX_LOCAL_CAPACITY:WARNING/)

  const invalid = spawnSync(process.execPath, [script, '--policy', 'surprise'], {
    cwd: root,
    env: localEnv,
    encoding: 'utf8',
  })
  assert.strictEqual(invalid.status, 2)
} finally {
  fs.rmSync(temp, { recursive: true, force: true })
}

console.log('LOCAL_CAPACITY_PREFLIGHT_FIXTURE:PASS')
