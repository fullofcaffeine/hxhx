#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
node - <<'JS'
const assert = require('node:assert/strict')
const report = require('./out/ocaml_lowering_report.json')
const boundary = report.functionResultBoundaries.find(value => value.sourceFieldName === 'optional')
assert(boundary, 'the module-level function must retain its checked result conversion')
assert.equal(boundary.source, 'non-generic-static-nullable-enum-declaration')
assert.equal(boundary.result.conversion, 'box-exact-enum-to-nullable-enum')
assert(boundary.nullableEnum, 'the result conversion must retain its exact enum proof')
JS
echo "MODULE_NULLABLE_ENUM_RESULT:PASS"
