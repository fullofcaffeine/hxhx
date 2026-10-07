#!/usr/bin/env bash
set -euo pipefail
diff -u expected.stdout <("${HAXE_BIN:-haxe}" -cp src -main Main --interp)

fixture_root="$(cd ../../../.. && pwd)"
inspection_work="$(mktemp -d)"
trap 'rm -rf "$inspection_work"' EXIT

"${HAXE_BIN:-haxe}" -cp "$fixture_root/packages/reflaxe.ocaml/src" \
  --macro 'nullSafety("reflaxe.ocaml")' -D reflaxe_runtime \
  -main reflaxe.ocaml.tooling.ReflaxeOcamlRun --neko "$inspection_work/inspect.n"
neko "$inspection_work/inspect.n" inspect --project "$PWD" --output out \
  --require-lowering --json > "$inspection_work/valid.json"

node - "$inspection_work/valid.json" "$inspection_work/invalid" <<'NODE'
const assert = require('assert/strict')
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
assert.equal(report.summary.valid, true)
const boundaries = report.lowering.functionResultBoundaries.filter(entry => entry.source === 'nested-nullable-enum-result')
assert.equal(boundaries.length, 2)
for (const boundary of boundaries) {
  assert.equal(boundary.callableBoundaryId, null)
  assert.equal(boundary.result.outputSemanticTypeId, 'Null<Term>')
  assert.equal(boundary.result.conversion, 'box-exact-enum-to-nullable-enum')
  assert.equal(boundary.proofId, 'nested-nullable-enum-result-only-v1')
}
// Inspector mutations need source artifacts, not another copy of the native build.
fs.cpSync('out', process.argv[3], {recursive: true, filter: path => !path.split(/[\\/]/).includes('_build')})
NODE

for mutation in callable-id enum-name source-kind missing-proof old-schema; do
  node - "$inspection_work/invalid/ocaml_lowering_report.json" "$mutation" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const reportJson = require('../../../../scripts/ci/ocaml-report-json')
const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
const boundary = report.functionResultBoundaries.find(entry => entry.source === 'nested-nullable-enum-result')
switch (process.argv[3]) {
  case 'callable-id': boundary.callableBoundaryId = 'nested-callable-boundary:000000000000000000000000'; break
  case 'enum-name': boundary.nullableEnum.semanticTypeId = 'OtherTerm'; break
  case 'source-kind': boundary.source = 'nested-nullable-enum-callable'; break
  case 'missing-proof': boundary.nullableEnum = null; break
  case 'old-schema': report.schemaVersion = 91; break
  default: throw new Error('Unknown mutation')
}
report.functionResultBoundaryRevision = `sha256:${crypto.createHash('sha256').update(reportJson(report.functionResultBoundaries)).digest('hex')}`
fs.writeFileSync(process.argv[2], `${JSON.stringify(report, null, 2)}\n`)
NODE
  if neko "$inspection_work/inspect.n" inspect --project "$PWD" --output "$inspection_work/invalid" \
    --require-lowering --json > "$inspection_work/rejected.json" 2>&1; then
    echo "Inspector accepted corrupted nullable callback evidence: $mutation" >&2
    exit 1
  fi
  if ! grep -Eiq 'function.result|representation|schema' "$inspection_work/rejected.json"; then
    cat "$inspection_work/rejected.json" >&2
    exit 1
  fi
done
echo 'NULLABLE_FUNCTION_VALUE_INSPECTION:PASS'
