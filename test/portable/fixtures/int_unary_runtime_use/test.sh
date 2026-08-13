#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
report="out/ocaml_lowering_report.json"
generated="out/Main.ml"
inspection="$(mktemp)"
trap 'rm -f "$inspection"' EXIT

node - "$report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 86
	|| report.intUnaryModel !== 'typed-ocaml-int-unary-v1'
	|| report.intUnaryCount !== 10
	|| report.intUnary?.length !== 10) {
	throw new Error('The lowering report does not contain the ten expected integer unary decisions')
}
const count = (field, value) => report.intUnary.filter(decision => decision[field] === value).length
if (count('operation', 'negate') !== 5
	|| count('operation', 'bitwise-not') !== 5
	|| count('operandCarrier', 'exact-int') !== 6
	|| count('operandCarrier', 'nullable-int') !== 4) {
	throw new Error(`Unexpected integer unary decision inventory: ${JSON.stringify(report.intUnary)}`)
}
for (const decision of report.intUnary) {
	const finalSymbol = decision.operation === 'negate' ? 'HxInt.neg' : 'HxInt.lognot'
	const expectedSymbols = decision.operandCarrier === 'nullable-int'
		? [finalSymbol, 'HxRuntime.hx_null']
		: [finalSymbol]
	if (decision.proofId !== 'int-unary-runtime-use-v1'
		|| !['ocaml-function-plans-v112', 'ocaml-nested-function-plans-v30', 'ocaml-standalone-expression-plans-v15'].includes(decision.pipelineRevision)
		|| decision.runtimeUseOccurrences.map(use => use.exactSymbol).join(',') !== expectedSymbols.join(',')) {
		throw new Error(`Incomplete integer unary authority: ${JSON.stringify(decision)}`)
	}
	const requirement = report.runtimeRequirements.find(entry => entry.id === `${decision.id}:runtime:haxe-int32-unary`)
	const expectedRoots = decision.operandCarrier === 'nullable-int' ? 'HxInt,HxRuntime' : 'HxInt'
	if (!requirement
		|| requirement.semanticCapability !== 'haxe-int32-unary'
		|| requirement.implementationFeature !== 'haxe-int32-unary-v1'
		|| requirement.rootModules.join(',') !== expectedRoots) {
		throw new Error(`Missing exact integer unary runtime requirement: ${decision.id}`)
	}
}
NODE

if [ "$(grep -Eo 'HxInt\.(neg|lognot)' "$generated" | wc -l | tr -d ' ')" -ne 10 ]; then
	echo "Generated Main.ml does not contain exactly ten integer unary helper calls" >&2
	exit 1
fi

haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output out --require-lowering --json >"$inspection"

node - "$inspection" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (report.schemaVersion !== 47
	|| !report.summary?.valid
	|| report.summary.intUnaryCount !== 10
	|| report.lowering?.intUnary?.length !== 10) {
	throw new Error('Public inspection did not preserve the ten integer unary decisions')
}
NODE

first="$(shasum -a 256 "$report" | awk '{print $1}')"
haxe build.hxml >/dev/null
second="$(shasum -a 256 "$report" | awk '{print $1}')"
if [ "$first" != "$second" ]; then
	echo "Integer unary lowering evidence changed across identical builds" >&2
	exit 1
fi
