#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
generated="out/Main.ml"
report="out/ocaml_lowering_report.json"
inspection_report="$(mktemp)"
invalid_log="$(mktemp)"
original_report="$(mktemp)"
trap 'cp "$original_report" "$report" 2>/dev/null || true; rm -f "$inspection_report" "$invalid_log" "$original_report"' EXIT
if [ ! -f "$generated" ]; then
	echo "Missing generated Reflect.compare fixture source" >&2
	exit 1
fi
cp "$report" "$original_report"

node - "$report" <<'NODE'
const fs = require('fs')
const reportPath = process.argv[2]
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
if (report.schemaVersion !== 66) {
	throw new Error(`Expected lowering schema 66, received ${report.schemaVersion}`)
}
if (report.reflectCompareModel !== 'typed-ocaml-reflect-compare-intrinsic-v1') {
	throw new Error(`Unexpected Reflect.compare plan model: ${report.reflectCompareModel}`)
}
if (report.reflectCompareCount !== 10 || report.reflectCompare.length !== 10) {
	throw new Error(`Expected ten typed Reflect.compare decisions, received ${report.reflectCompareCount}`)
}
const domains = report.reflectCompare.map(decision => decision.domain).sort()
if (JSON.stringify(domains) !== JSON.stringify(['float', 'float', 'float', 'int', 'int', 'string', 'string', 'string', 'string', 'string'])) {
	throw new Error(`Unexpected Reflect.compare domains: ${JSON.stringify(domains)}`)
}
for (const decision of report.reflectCompare) {
	if (decision.proofId !== `ocaml-reflect-compare-intrinsic-v1:${decision.domain}`
		|| !['ocaml-function-plans-v77', 'ocaml-standalone-expression-plans-v3'].includes(decision.pipelineRevision)) {
		throw new Error(`Incomplete Reflect.compare proof: ${JSON.stringify(decision)}`)
	}
}
NODE

if grep -q 'Reflect\.compare' "$generated"; then
	echo "A resolved Reflect.compare value escaped the typed target plan" >&2
	exit 1
fi
if grep -q 'HxReflect\.compare' "$generated"; then
	echo "The typed fixture reached the broad legacy object comparator" >&2
	exit 1
fi
if grep -Eq '__reflect_(left|right)_[0-9]+ : Obj\.t|Obj\.(magic|repr|obj) __reflect_(left|right)_[0-9]+' "$generated"; then
	echo "The typed comparator boundary widened through Obj conversions" >&2
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$inspection_report"

node - "$inspection_report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 43
	|| !report.summary?.valid
	|| report.summary.reflectCompareCount !== 10
	|| report.lowering?.reflectCompare?.length !== 10) {
	throw new Error('Public inspection did not preserve the ten typed Reflect.compare decisions')
}
NODE

# Change one proof and its inventory digest. Public inspection must reject the
# false claim before a user or another tool relies on it.
node - "$report" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const reportPath = process.argv[2]
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
report.reflectCompare[0].proofId = 'ocaml-reflect-compare-intrinsic-v1:invalid'
report.reflectCompareRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.reflectCompare)).digest('hex')}`
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$invalid_log" 2>&1; then
	echo "Public inspection accepted a false Reflect.compare domain proof" >&2
	exit 1
fi
if ! grep -Fq "incomplete domain proof" "$invalid_log"; then
	echo "Public inspection did not explain the false Reflect.compare domain proof" >&2
	cat "$invalid_log" >&2
	exit 1
fi
cp "$original_report" "$report"
