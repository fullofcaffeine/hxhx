#!/usr/bin/env node

const fs = require('fs')
const os = require('os')
const path = require('path')
const cp = require('child_process')

const root = path.resolve(__dirname, '../..')
const script = path.join(root, 'scripts/ci/full1-phase-timing.js')
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'full1-phase-timing-'))
const jsonl = path.join(tmpDir, 'timings.jsonl')
const jsonOut = path.join(tmpDir, 'timings.summary.json')
const markdownOut = path.join(tmpDir, 'timings.md')

function fail(message) {
  console.error(`[full1-phase-timing-fixture-test] ${message}`)
  process.exit(1)
}

function run(args) {
  const result = cp.spawnSync(process.execPath, [script, ...args], {
    cwd: root,
    encoding: 'utf8',
  })
  if (result.status !== 0) {
    fail(`${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`)
  }
}

run([
  'append',
  '--jsonl', jsonl,
  '--workflow', 'fixture',
  '--job', 'build_hxhx',
  '--phase', 'prepare_haxelib_repo',
  '--started-ms', '1000',
  '--ended-ms', '2500',
  '--status', 'pass',
  '--exit-code', '0',
])

run([
  'append',
  '--jsonl', jsonl,
  '--workflow', 'fixture',
  '--job', 'build_hxhx',
  '--phase', 'build_hxhx_binary',
  '--started-ms', '3000',
  '--ended-ms', '5500',
  '--status', 'pass',
  '--exit-code', '0',
])

run([
  'summarize',
  '--jsonl', jsonl,
  '--json-out', jsonOut,
  '--markdown-out', markdownOut,
])

const summary = JSON.parse(fs.readFileSync(jsonOut, 'utf8'))
if (summary.schema !== 'full1-phase-timing-summary.v1') fail('summary schema mismatch')
if (summary.phase_count !== 2) fail(`expected 2 phases, got ${summary.phase_count}`)
if (summary.total_duration_ms !== 4000) fail(`expected total 4000ms, got ${summary.total_duration_ms}`)
if (summary.failed_phase_count !== 0) fail(`expected no failed phases, got ${summary.failed_phase_count}`)

const markdown = fs.readFileSync(markdownOut, 'utf8')
if (!markdown.includes('| prepare_haxelib_repo | pass | 0 | 1.500 |')) {
  fail('markdown missing prepare_haxelib_repo row')
}
if (!markdown.includes('Total measured phase time: 4.000s')) {
  fail('markdown missing total duration')
}

fs.rmSync(tmpDir, { recursive: true, force: true })
console.log('[full1-phase-timing-fixture-test] ok')
