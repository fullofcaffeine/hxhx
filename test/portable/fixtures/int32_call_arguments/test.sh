#!/usr/bin/env bash
set -euo pipefail
"${HAXE_BIN:-haxe}" -cp src -main Main --interp > out/upstream.stdout
diff -u expected.stdout out/upstream.stdout
node - out/ocaml_lowering_report.json <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const hex = report.calls.filter(call => call.calleeId === 'StringTools|StringTools::hex');
assert.equal(hex.length, 2, 'each field conversion must retain its own call plan');
const ordinary = report.calls.filter(call => call.calleeId === 'Main|IntegerCalls::describe');
assert.equal(ordinary.length, 2, 'ordinary optional methods need the same conversion proof');
for (const call of [...hex, ...ordinary]) {
 assert.equal(call.arguments[0].conversion, 'identity');
 assert.equal(call.arguments[0].inputCarrierTypeId, 'int');
}
assert(ordinary.some(call => call.arguments[1].conversion === 'box-exact-int-to-nullable-int'));
assert(ordinary.some(call => call.arguments[1].conversion === 'materialize-omitted-nullable-int'));
NODE
