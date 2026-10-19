#!/usr/bin/env node
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const fixture = __dirname
const root = path.resolve(fixture, '../../../..')
const output = path.join(fixture, 'out')
const report = JSON.parse(fs.readFileSync(path.join(output, 'ocaml_lowering_report.json'), 'utf8'))
const calls = value => value.calls.filter(call => call.kind === 'generic-instance-haxe-method')
const sourceCalls = calls(report).filter(call => call.calleeId.endsWith('::withSource'))
assert.equal(sourceCalls.length, 2, 'both enum-bearing calls need a checked callback conversion')
assert(sourceCalls.some(call => call.genericInstanceTarget.arguments.length === 3))
assert(sourceCalls.some(call => call.genericInstanceTarget.arguments.length === 4))
for (const call of sourceCalls) {
  assert.deepEqual(call.genericInstanceTarget.optionalParameterIndices, [3])
  assert.equal(call.genericInstanceTarget.argumentShapes[0].kind, 'enum-argument')
}

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'ocaml-optional-generic-report-'))
const cases = []
try {
  function corrupt(label, pattern, mutate) {
    const destination = path.join(temporary, String(cases.length))
    fs.cpSync(output, destination, { recursive: true, filter: source => path.basename(source) !== '_build' })
    const changed = structuredClone(report)
    const call = calls(changed).find(entry => entry.calleeId.endsWith('::withSource')
      && entry.genericInstanceTarget.arguments.length === 3)
    mutate(call)
    fs.writeFileSync(path.join(destination, 'ocaml_lowering_report.json'), JSON.stringify(changed))
    cases.push({ label, pattern, destination })
  }
  corrupt('omitted required argument', /omitted slot|optional/i, call => {
    call.genericInstanceTarget.optionalParameterIndices = []
  })
  corrupt('duplicate optional index', /optional parameter order/i, call => {
    call.genericInstanceTarget.optionalParameterIndices = [3, 3]
  })
  corrupt('non-integer optional index', /parameter index/i, call => {
    call.genericInstanceTarget.optionalParameterIndices = [3.5]
  })
  corrupt('omitted argument consumes a source expression', /invalid materialization/i, call => {
    call.evaluationSchedule.find(step => step.kind === 'materialize-omitted-argument').sourceArgumentIndex = 3
  })
  corrupt('omitted argument uses a supplied argument step', /invalid materialization/i, call => {
    call.evaluationSchedule.find(step => step.kind === 'materialize-omitted-argument').kind = 'materialize-argument'
  })
  corrupt('class proof used for an enum', /enum.*representation|representation.*enum/i, call => {
    const target = call.genericInstanceTarget
    function replace(node) {
      if (node.kind === 'enum-argument') node.enumRepresentationId = target.receiverRepresentationId
      for (const child of node.children) replace(child)
    }
    replace(target.declaration)
    replace(target.instantiation)
    target.argumentShapes.forEach(replace)
  })
  corrupt('argument proof used for an enum result', /enum.*argument|argument.*enum/i, call => {
    const target = call.genericInstanceTarget
    const shape = structuredClone(target.argumentShapes[0])
    target.declaration.children[target.declaration.children.length - 1] = shape
    target.instantiation.children[target.instantiation.children.length - 1] = shape
    target.resultShape = shape
    target.result = { kind: 'identity', parameter: null, children: [] }
  })
  const inspected = spawnSync(process.env.HAXE_BIN || 'haxe', [
    '-cp', 'packages/reflaxe.ocaml/src',
    '-cp', path.join(fixture, '../module_generic_signature'),
    '--macro', 'nullSafety("reflaxe.ocaml")', '--run', 'InspectReports',
    fixture, output, ...cases.map(entry => entry.destination)
  ], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'], timeout: 600000, maxBuffer: 24 * 1024 * 1024 })
  assert.equal(inspected.status, 0, inspected.stdout + (inspected.stderr || ''))
  const inspectedReports = JSON.parse(inspected.stdout)
  assert.equal(inspectedReports.length, cases.length + 1)
  assert.equal(inspectedReports[0].summary.valid, true, JSON.stringify(inspectedReports[0]))
  for (const [index, entry] of cases.entries()) {
    const result = inspectedReports[index + 1]
    assert.equal(result.summary.valid, false, entry.label)
    assert.match(result.lowering.message, entry.pattern, entry.label)
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true })
}
console.log('OPTIONAL_GENERIC_CALL_REPORT_NEGATIVES:PASS')
