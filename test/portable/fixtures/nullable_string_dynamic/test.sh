#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
node <<'NODE'
const assert = require('node:assert/strict')
const report = require('./out/ocaml_lowering_report.json')
const conversions = report.localConversions.filter(value => value.inputSemanticTypeId === 'Null<String>' && value.outputSemanticTypeId === 'Dynamic')
assert.equal(conversions.length, 6, 'each nullable print input needs its own conversion')
for (const conversion of conversions) {
  assert.equal(conversion.inputCarrierTypeId, 'string')
  assert.equal(conversion.outputCarrierTypeId, 'Obj.t')
  assert.equal(conversion.conversion, 'box-concrete-to-dynamic')
  assert.equal(conversion.unsafeOperation.operation, 'obj-repr-concrete-to-dynamic')
}
NODE
