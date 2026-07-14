#!/usr/bin/env node

/**
 * Exercise strict M7 artifact receipts and the no-build dry-run contract.
 */

const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')
const { buildReport, marker, schema, validateReport } = require('./m7-shared-artifacts.js')

const root = path.resolve(__dirname, '..', '..')
const runner = path.join(root, 'scripts', 'hxhx', 'run-replacement-ready.sh')
const workflow = path.join(root, '.github', 'workflows', 'gate-m7.yml')
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-m7-shared-artifacts-'))

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || fixture,
    env: options.env || process.env,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024
  })
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n${result.stdout}\n${result.stderr}`)
  }
  return result.stdout
}

function write(filePath, content, mode) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content)
  if (mode) fs.chmodSync(filePath, mode)
}

function expectFailure(label, action, pattern) {
  try {
    action()
  } catch (error) {
    if (!pattern.test(error.message)) {
      throw new Error(`${label} failed for the wrong reason: ${error.message}`)
    }
    return
  }
  throw new Error(`${label} unexpectedly passed`)
}

try {
  run('git', ['init', '-q'])
  run('git', ['config', 'user.email', 'm7-fixture@example.invalid'])
  run('git', ['config', 'user.name', 'M7 Fixture'])
  write(path.join(fixture, 'packages', 'hxhx', 'bootstrap_out', 'dune'), '(executable (name out))\n')
  write(path.join(fixture, 'packages', 'hxhx-macro-host', 'bootstrap_out', 'dune'), '(executable (name out))\n')
  write(path.join(fixture, 'tracked.txt'), 'clean\n')
  run('git', ['add', '.'])
  run('git', ['commit', '-q', '-m', 'fixture'])

  const hxhxBin = path.join(fixture, '.artifacts', 'gate-m7-shared', 'hxhx.exe')
  const macroHostBin = path.join(fixture, '.artifacts', 'gate-m7-shared', 'hxhx-macro-host.exe')
  write(hxhxBin, '#!/bin/sh\nexit 0\n', 0o755)
  write(macroHostBin, '#!/bin/sh\nexit 0\n', 0o755)

  const report = buildReport({ root: fixture, hxhxBin, macroHostBin })
  const commit = run('git', ['rev-parse', 'HEAD']).trim()
  validateReport({ root: fixture, report, expectedCommit: commit })
  if (report.schema !== schema || report.marker !== marker) throw new Error('valid receipt lost its schema or marker')
  if (path.isAbsolute(report.artifacts.hxhx.path)) throw new Error('receipt leaked an absolute artifact path')

  fs.appendFileSync(hxhxBin, '# changed\n')
  expectFailure('changed artifact digest', () => validateReport({ root: fixture, report, expectedCommit: commit }), /digest changed/)
  write(hxhxBin, '#!/bin/sh\nexit 0\n', 0o755)

  write(path.join(fixture, 'tracked.txt'), 'dirty\n')
  expectFailure('changed tracked source', () => validateReport({ root: fixture, report, expectedCommit: commit }), /not clean|content changed|status changed/)
  run('git', ['checkout', '--', 'tracked.txt'])

  expectFailure('cross-commit receipt', () => validateReport({ root: fixture, report, expectedCommit: '0'.repeat(40) }), /expected commit/)
  expectFailure('legacy schema', () => validateReport({ root: fixture, report: { ...report, schema: 'm7-shared-artifacts.v0' }, expectedCommit: commit }), /schema/)
  expectFailure('stage0-enabled receipt', () => validateReport({
    root: fixture,
    report: { ...report, build: { ...report.build, stage0Forbidden: false } },
    expectedCommit: commit
  }), /stage0-forbidden/)
  expectFailure('absolute artifact path', () => validateReport({
    root: fixture,
    report: {
      ...report,
      artifacts: { ...report.artifacts, hxhx: { ...report.artifacts.hxhx, path: hxhxBin } }
    },
    expectedCommit: commit
  }), /repository-relative/)

  const dryRun = run('bash', [runner], {
    cwd: root,
    env: {
      ...process.env,
      HXHX_M7_DRY_RUN: '1',
      HXHX_M7_PROFILE: 'full',
      HXHX_M7_STRICT: '1',
      HXHX_M7_REQUIRE_PLUGIN_MATRIX: '1'
    }
  })
  for (const expected of [
    'M7_SHARED_ARTIFACTS:DRY_RUN',
    '== M7 check: ci:guards',
    '== M7 check: stage0-policy-release',
    '== M7 check: gate2-display',
    '== M7 check: builtin-target-smoke (strict lanes)',
    '== M7 check: gate1-unit-macro',
    '== M7 check: gate2-runci-macro',
    '== M7 check: gate3-runci-targets',
    '== M7 check: plugin-matrix',
    'M7_STRICT_STAGE0:PASS',
    'M7_REPLACEMENT_READY:PASS'
  ]) {
    if (!dryRun.includes(expected)) throw new Error(`strict M7 dry run is missing: ${expected}`)
  }

  const workflowSource = fs.readFileSync(workflow, 'utf8')
  for (const expected of [
    'timeout-minutes: 180',
    "grep -q '^M7_SHARED_ARTIFACTS:PASS'",
    '.artifacts/gate-m7-shared/receipt.json'
  ]) {
    if (!workflowSource.includes(expected)) throw new Error(`M7 workflow contract is missing: ${expected}`)
  }

  console.log('[m7-shared-artifacts-fixture-test] ok')
} finally {
  fs.rmSync(fixture, { recursive: true, force: true })
}
