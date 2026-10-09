#!/usr/bin/env bash
set -euo pipefail

upstream_output="$(../../../../node_modules/.bin/haxe -cp src -main Main --interp)"
diff -u expected.stdout <(printf '%s\n' "$upstream_output")

node <<'NODE'
const assert = require('node:assert/strict')
const fs = require('node:fs')
const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
const calls = report.calls.filter(call => call.functionId.startsWith('standalone:')
  && call.standardArrayTarget?.operation === 'push')
assert.equal(calls.length, 3, 'both comprehensions and the explicit initializer push need plans')
for (const call of calls) {
  assert.equal(call.standardArrayTarget.resultSemanticTypeId, 'Int')
  assert.equal(call.standardArrayTarget.runtimeFunction, 'push')
  assert.deepEqual(call.evaluationSchedule.map(step => step.kind),
    ['materialize-receiver', 'materialize-argument', 'invoke-callee'])
  assert(report.runtimeRequirements.some(requirement => requirement.decisionId === call.id
    && requirement.rootModules.includes('HxArray')), 'initializer push has no runtime reason')
}
NODE
