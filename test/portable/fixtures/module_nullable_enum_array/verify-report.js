#!/usr/bin/env node
// Exercise public inspection with independently corrupted, integrity-resealed reports.
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const fixture = __dirname
const root = path.resolve(fixture, '../../../..')
const output = path.join(fixture, 'out')
const report = JSON.parse(fs.readFileSync(path.join(output, 'ocaml_lowering_report.json'), 'utf8'))
const selected = value => value.controls.find(control => control.functionId.startsWith('Collector|Collector|')
  && control.functionId.includes('|function|collect|') && control.kind === 'return')
const control = selected(report)
assert(control, 'the faithful collector must retain its early return')
assert.equal(control.payload, null)
assert.equal(control.mechanism, 'runtime-void-return-signal')
assert(!report.functionResultBoundaries.some(boundary => boundary.functionId === control.functionId),
  'the regression must exercise typed Void coverage without a separate callable-result record')

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-void-array-report-'))
const cases = []
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit'], timeout: 600000, maxBuffer: 32 * 1024 * 1024 })
  assert.equal(result.status, 0, result.stdout + (result.stderr || '') + String(result.error || ''))
  return result.stdout
}
try {
  const reseal = path.join(temporary, 'reseal.n')
  run(process.env.HAXE_BIN || 'haxe', ['-cp', 'scripts/ci', '-cp', 'packages/reflaxe.ocaml/src',
    '-D', 'reflaxe_runtime', '-main', 'RecomputeLoweringControlRevision', '--neko', reseal])
  function corrupt(label, pattern, mutate) {
    const destination = path.join(temporary, String(cases.length))
    fs.cpSync(output, destination, { recursive: true, filter: source => path.basename(source) !== '_build' })
    const changed = structuredClone(report)
    mutate(selected(changed), changed)
    const filename = path.join(destination, 'ocaml_lowering_report.json')
    fs.writeFileSync(filename, JSON.stringify(changed))
    run('neko', [reseal, filename])
    cases.push({ label, pattern, destination })
  }
  corrupt('value mechanism for payloadless return', /exact-value return capability or payload/i,
    entry => { entry.mechanism = 'runtime-return-signal' })
  corrupt('wrong Void proof', /effect-only Void return contract/i,
    entry => { entry.proofId = 'invalid-void-proof' })
  corrupt('wrong runtime capability', /effect-only Void return contract/i,
    entry => { entry.runtimeCapabilityId = 'hxhx-runtime:function-return-signal-v1' })
  corrupt('return targets another function', /invalid return target, effect, or tag policy/i,
    entry => { entry.targetId = 'another-function' })
  // The admission still promises one return, so the report must not pass with no decision for it.
  corrupt('missing admitted return', /disagrees with its admitted decision counts/i, (entry, changed) => {
    changed.controls = changed.controls.filter(candidate => candidate.id !== entry.id)
    changed.controlCount = changed.controls.length
  })
  const results = JSON.parse(run(process.env.HAXE_BIN || 'haxe', [
    '-cp', 'packages/reflaxe.ocaml/src', '-cp', path.join(fixture, '../module_generic_signature'),
    '--macro', 'nullSafety("reflaxe.ocaml")', '--run', 'InspectReports', fixture, output,
    ...cases.map(entry => entry.destination)
  ]))
  assert.equal(results.length, cases.length + 1)
  assert.equal(results[0].summary.valid, true, JSON.stringify(results[0]))
  for (const [index, entry] of cases.entries()) {
    assert.equal(results[index + 1].summary.valid, false, entry.label)
    assert.match(results[index + 1].lowering.message, entry.pattern, entry.label)
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}
console.log('VOID_RETURN_COVERAGE_NEGATIVES:PASS')
