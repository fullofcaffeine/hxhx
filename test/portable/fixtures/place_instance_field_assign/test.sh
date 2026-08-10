#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd ../../../.. && pwd)"
source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
invalid_output="out-invalid-int-runtime-use-$$"
invalid_log="$(mktemp)"
oracle_dir="$(mktemp -d)"
trap 'rm -f "$invalid_log"; rm -rf "$invalid_output" "$oracle_dir"' EXIT
if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated instance-field source or lowering report" >&2
	exit 1
fi

# Haxe eval and Neko are independent behavior oracles for the assignment and
# update operations. They expose uninitialized primitive fields as null, while
# this target's separately tested exact-carrier policy initializes them to zero
# or false. Exclude only those two pre-operation observations; every mutation,
# evaluation-order event, old/new result, and Int32 overflow line must match.
haxe -cp src --run Main >"$oracle_dir/eval.stdout"
haxe -cp src -main Main -neko "$oracle_dir/main.n"
neko "$oracle_dir/main.n" >"$oracle_dir/neko.stdout"
grep -vE '^(initial|bool_initial)=' expected.stdout >"$oracle_dir/expected-mutations.stdout"
grep -vE '^(initial|bool_initial)=' "$oracle_dir/eval.stdout" >"$oracle_dir/eval-mutations.stdout"
grep -vE '^(initial|bool_initial)=' "$oracle_dir/neko.stdout" >"$oracle_dir/neko-mutations.stdout"
diff -u "$oracle_dir/expected-mutations.stdout" "$oracle_dir/eval-mutations.stdout"
diff -u "$oracle_dir/expected-mutations.stdout" "$oracle_dir/neko-mutations.stdout"

if ! grep -q '^type holder_t = .*mutable value : int' "$source_file"; then
	echo "Holder.value must use the exact Int field carrier selected before emission" >&2
	exit 1
fi
if ! grep -q 'value = 0.*: holder_t' "$source_file"; then
	echo "Holder.value must use the exact Int zero default selected before emission" >&2
	exit 1
fi
if ! grep -q '^type holder_t = .*mutable ready : bool' "$source_file"; then
	echo "Holder.ready must use the exact Bool field carrier selected before emission" >&2
	exit 1
fi
if ! grep -q 'ready = false.*: holder_t' "$source_file"; then
	echo "Holder.ready must use the exact Bool false default selected before emission" >&2
	exit 1
fi
if ! grep -q '^type holder_t = .*mutable optionalCount : Obj.t.*mutable optionalFlag : Obj.t' "$source_file"; then
	echo "Exact nullable primitive fields must use the Obj.t carriers selected before emission" >&2
	exit 1
fi
if ! grep -q 'optionalCount = HxRuntime.hx_null.*optionalFlag = HxRuntime.hx_null.*: holder_t' "$source_file"; then
	echo "Exact nullable primitive fields must use direct HxRuntime.hx_null defaults" >&2
	exit 1
fi
if ! grep -q 'value = Obj.magic (HxRuntime.hx_null).*: abstractholder_t' "$source_file"; then
	echo "WrappedInt fields must remain outside the exact core Int field decision" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decision = report.representations.find(item => item.id === 'representation:Int:instance-field')
const boolDecision = report.representations.find(item => item.id === 'representation:Bool:instance-field')
const nullableIntDecision = report.representations.find(item => item.id === 'representation:Null<Int>:instance-field')
const nullableBoolDecision = report.representations.find(item => item.id === 'representation:Null<Bool>:instance-field')
const boolAssignment = report.plans.find(item =>
	item.nodeKind === 'simple-assignment'
	&& item.semanticTypeId === 'Bool'
	&& item.carrierTypeId === 'bool'
	&& item.place?.representationId === boolDecision?.id)
const intMutations = report.plans.filter(item =>
	item.nodeKind === 'compound-assignment'
	|| item.nodeKind === 'int-update')
if (!decision
	|| decision.carrierTypeId !== 'int'
	|| decision.implicitDefaultPolicy !== 'exact-int-zero') {
	throw new Error('the lowering report did not preserve the exact Int instance-field carrier/default decision')
}
if (!boolDecision
	|| boolDecision.carrierTypeId !== 'bool'
	|| boolDecision.implicitDefaultPolicy !== 'exact-bool-false'
	|| !boolAssignment) {
	throw new Error('the lowering report did not preserve the exact Bool field/default/simple-assignment decision')
}
if (!nullableIntDecision
	|| nullableIntDecision.carrierTypeId !== 'Obj.t'
	|| nullableIntDecision.implicitDefaultPolicy !== 'runtime-null-sentinel'
	|| !nullableBoolDecision
	|| nullableBoolDecision.carrierTypeId !== 'Obj.t'
	|| nullableBoolDecision.implicitDefaultPolicy !== 'runtime-null-sentinel'
	|| nullableIntDecision.id === nullableBoolDecision.id) {
	throw new Error('the lowering report did not preserve distinct exact nullable primitive field/default decisions')
}
if (intMutations.length === 0
	|| intMutations.some(item => item.runtimeUseOccurrences?.length !== 1
		|| item.runtimeUseOccurrences[0].exactSymbol !== 'HxInt.add'
		|| item.runtimeUseOccurrences[0].requirementId !== item.runtimeRequirementIds[0])) {
	throw new Error('each sealed instance-field Int mutation must own its exact HxInt.add runtime occurrence')
}
NODE

cp -R out "$invalid_output"
node - "$invalid_output/ocaml_lowering_report.json" <<'NODE'
const fs = require('fs')
const path = process.argv[2]
const report = JSON.parse(fs.readFileSync(path, 'utf8'))
const mutation = report.plans.find(item =>
	(item.nodeKind === 'compound-assignment' || item.nodeKind === 'int-update')
	&& item.runtimeUseOccurrences?.length === 1)
if (!mutation) {
	throw new Error('the fixture has no instance-field Int runtime occurrence to corrupt')
}
mutation.runtimeUseOccurrences[0].ownerId = 'wrong-owner'
fs.writeFileSync(path, `${JSON.stringify(report, null, 2)}\n`)
NODE

if haxe -cp "$ROOT/packages/reflaxe.ocaml/src" \
	--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
	inspect --project "$PWD" --output "$invalid_output" --require-lowering --json >"$invalid_log" 2>&1; then
	echo "Public inspection accepted an Int mutation whose runtime permission belongs to another plan" >&2
	exit 1
fi
if ! grep -Fq "disagrees with its sealed operator step" "$invalid_log"; then
	echo "Public inspection rejected the wrong Int runtime owner without the expected actionable reason" >&2
	cat "$invalid_log" >&2
	exit 1
fi

echo "INSTANCE_FIELD_REPRESENTATION_SOURCE_SHAPE:PASS"
