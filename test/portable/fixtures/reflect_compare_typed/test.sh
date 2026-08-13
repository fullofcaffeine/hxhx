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
if (report.schemaVersion !== 85) {
	throw new Error(`Expected lowering schema 84, received ${report.schemaVersion}`)
}
if (report.reflectCompareModel !== 'typed-ocaml-reflect-compare-intrinsic-v4') {
	throw new Error(`Unexpected Reflect.compare plan model: ${report.reflectCompareModel}`)
}
if (report.reflectCompareCount !== 16 || report.reflectCompare.length !== 16) {
	throw new Error(`Expected sixteen typed Reflect.compare decisions, received ${report.reflectCompareCount}`)
}
const domains = report.reflectCompare.map(decision => decision.domain).sort()
if (JSON.stringify(domains) !== JSON.stringify([
	'float', 'float', 'float',
	'int', 'int',
	'nullable-string', 'nullable-string', 'nullable-string', 'nullable-string', 'nullable-string', 'nullable-string',
	'string', 'string', 'string', 'string', 'string'
])) {
	throw new Error(`Unexpected Reflect.compare domains: ${JSON.stringify(domains)}`)
}
for (const decision of report.reflectCompare) {
	if (decision.proofId !== `ocaml-reflect-compare-intrinsic-v2:${decision.domain}`
		|| !['ocaml-function-plans-v108', 'ocaml-standalone-expression-plans-v14'].includes(decision.pipelineRevision)) {
		throw new Error(`Incomplete Reflect.compare proof: ${JSON.stringify(decision)}`)
	}
	const stringRequirementId = `${decision.id}:runtime:haxe-reflect-compare-string-null`
	const failureRequirementId = `${decision.id}:runtime:haxe-reflect-compare-failure`
	const expected = {
		int: {requirements: [], uses: []},
		float: {requirements: [failureRequirementId], uses: [[failureRequirementId, 'HxRuntime.hx_throw', 'throw-invalid-comparison']]},
		string: {requirements: [stringRequirementId, failureRequirementId], uses: [
			[stringRequirementId, 'HxString.isNull', 'left-null-check'],
			[stringRequirementId, 'HxString.isNull', 'right-null-check'],
			[failureRequirementId, 'HxRuntime.hx_throw', 'throw-invalid-comparison']
		]},
		'nullable-string': {requirements: [stringRequirementId], uses: [
			[stringRequirementId, 'HxString.isNull', 'left-null-check'],
			[stringRequirementId, 'HxString.isNull', 'right-null-check']
		]}
	}[decision.domain]
	if (JSON.stringify(decision.runtimeRequirementIds) !== JSON.stringify(expected.requirements)
		|| JSON.stringify(decision.runtimeUseOccurrences.map(use => [use.requirementId, use.exactSymbol, use.role])) !== JSON.stringify(expected.uses)) {
		throw new Error(`Reflect.compare has the wrong exact runtime inventory: ${JSON.stringify(decision)}`)
	}
	for (const requirementId of expected.requirements) {
		const expectedRoot = requirementId === stringRequirementId ? 'HxString' : 'HxRuntime'
		if (!report.runtimeRequirements.some(requirement => requirement.id === requirementId
			&& requirement.rootModules?.join(',') === expectedRoot)) {
			throw new Error(`Reflect.compare runtime requirement is missing from the request ledger: ${requirementId}`)
		}
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
if (report.schemaVersion !== 47
	|| !report.summary?.valid
	|| report.summary.reflectCompareCount !== 16
	|| report.lowering?.reflectCompare?.length !== 16) {
	throw new Error('Public inspection did not preserve the sixteen typed Reflect.compare decisions')
}
NODE

# The report stores the selected comparison and its runtime dependencies in two
# separate sections. Change one String null-check dependency and refresh its
# digest. Inspection must compare both sections before it accepts the report.
node - "$report" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const reportPath = process.argv[2]
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
const requirement = report.runtimeRequirements.find(entry => entry.semanticCapability === 'haxe-reflect-compare-string-null')
if (!requirement)
	throw new Error('Missing String null-check requirement for corruption check')
requirement.semanticCapability = 'haxe-reflect-compare-failure'
report.runtimeRequirementRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.runtimeRequirements)).digest('hex')}`
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$invalid_log" 2>&1; then
	echo "Public inspection accepted a contradictory Reflect.compare runtime requirement" >&2
	exit 1
fi
if ! grep -Fq "disagrees with its sealed domain" "$invalid_log"; then
	echo "Public inspection did not explain the contradictory Reflect.compare runtime requirement" >&2
	cat "$invalid_log" >&2
	exit 1
fi
cp "$original_report" "$report"

# Change one proof and its inventory digest. Public inspection must reject the
# false claim before a user or another tool relies on it.
node - "$report" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const reportPath = process.argv[2]
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
report.reflectCompare[0].proofId = 'ocaml-reflect-compare-intrinsic-v2:invalid'
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

# A report digest cannot turn a different private helper into valid compiler
# authority. Change the exact symbol, refresh the surrounding inventory digest,
# and require inspection to reject the contradiction against the sealed domain.
node - "$report" <<'NODE'
const crypto = require('crypto')
const fs = require('fs')
const reportPath = process.argv[2]
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
const exceptional = report.reflectCompare.find(decision => decision.domain === 'float')
if (!exceptional)
	throw new Error('Missing exceptional Reflect.compare decision for corruption check')
exceptional.runtimeUseOccurrences[0].exactSymbol = 'HxRuntime.hx_throw_typed'
report.reflectCompareRevision = `sha256:${crypto.createHash('sha256').update(JSON.stringify(report.reflectCompare)).digest('hex')}`
fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$invalid_log" 2>&1; then
	echo "Public inspection accepted a conflicting Reflect.compare runtime helper" >&2
	exit 1
fi
if ! grep -Fq "stale or conflicting runtime-use evidence" "$invalid_log"; then
	echo "Public inspection did not explain the conflicting Reflect.compare runtime helper" >&2
	cat "$invalid_log" >&2
	exit 1
fi
cp "$original_report" "$report"
