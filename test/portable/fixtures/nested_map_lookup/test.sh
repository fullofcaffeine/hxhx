#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)
node <<'NODE'
const assert = require('node:assert/strict')
const report = require('./out/ocaml_lowering_report.json')
const aliases = report.iMapStorageAliases.filter(value => value.nullPolicy === 'check-null-and-unbox')
assert.equal(aliases.length, 8, 'every immediate nested-map receiver needs its own checked recovery')
assert.deepEqual([...new Set(aliases.map(value => value.standardKeyKind))].sort(), ['int', 'object-identity', 'string'])
for (const alias of aliases) {
  assert.equal(alias.sourceCarrierTypeId, 'Obj.t')
  assert.equal(alias.proofId, 'typed-standard-map-storage-alias-v3')
  assert.deepEqual(alias.runtimeUseOccurrences.map(value => value.exactSymbol), ['HxRuntime.is_null', 'HxRuntime.hx_throw_typed'])
}
NODE
