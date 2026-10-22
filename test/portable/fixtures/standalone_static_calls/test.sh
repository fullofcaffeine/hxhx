#!/usr/bin/env bash
set -euo pipefail

diff -u expected.stdout <(haxe -cp src -main Main --interp)
node <<'NODE'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
const calls = report.calls.filter(call => call.functionId.startsWith('standalone:')
  && call.sourceTypeName === 'Calls')
assert.equal(calls.length, 3)
const optional = calls.filter(call => call.sourceFieldName === 'optionalInt')
assert.equal(optional.length, 2)
assert(optional.every(call => call.arguments.length === 1 && call.arguments[0].parameterOptional === true))
assert.equal(optional.filter(call => call.evaluationSchedule[0].kind === 'materialize-omitted-argument').length, 1)
assert.equal(optional.filter(call => call.evaluationSchedule[0].kind === 'materialize-argument').length, 1)
const effect = calls.find(call => call.sourceFieldName === 'run')
assert(effect)
assert.equal(effect.resultKind, 'effect-only-void')
assert.equal(effect.result, null)
assert.deepEqual(effect.evaluationSchedule.map(step => step.kind), ['invoke-callee'])
NODE
