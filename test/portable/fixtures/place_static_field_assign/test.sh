#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
external_source_file="out/ExternalHolder.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$source_file" ] || [ ! -f "$external_source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated static-field source or lowering report" >&2
	exit 1
fi

declaration_count="$(grep -c '^let sameModuleValue = ref ' "$source_file" || true)"
if [ "$declaration_count" -ne 1 ]; then
	echo "Expected exactly one OCaml ref cell for Main.sameModuleValue, found $declaration_count" >&2
	exit 1
fi

declaration_line="$(grep -n '^let sameModuleValue = ref ' "$source_file" | cut -d: -f1)"
worker_line="$(grep -n '^let samemoduleworker_run = ' "$source_file" | cut -d: -f1)"
initializer_count="$(grep -c '^let __init_sameModuleValue = sameModuleValue := 20$' "$source_file" || true)"
if [ "$declaration_line" -ge "$worker_line" ] || [ "$initializer_count" -ne 1 ]; then
	echo "The shared cell must be declared before SameModuleWorker and initialized exactly once by Main" >&2
	exit 1
fi

bool_declaration_count="$(grep -c '^let sameModuleBool = ref (false : bool)$' "$source_file" || true)"
bool_declaration_line="$(grep -n '^let sameModuleBool = ref (false : bool)$' "$source_file" | cut -d: -f1)"
if [ "$bool_declaration_count" -ne 1 ] || [ "$bool_declaration_line" -ge "$worker_line" ]; then
	echo "The shared exact Bool cell must be declared once with false before SameModuleWorker" >&2
	exit 1
fi

object_declaration_count="$(grep -c '^let sameModuleObject = ref ' "$source_file" || true)"
if [ "$object_declaration_count" -ne 1 ]; then
	echo "Expected exactly one OCaml ref cell for Main.sameModuleObject, found $object_declaration_count" >&2
	exit 1
fi

object_type_line="$(grep -n '^type samemoduleworker_t = ' "$source_file" | cut -d: -f1)"
object_declaration_line="$(grep -n '^let sameModuleObject = ref ' "$source_file" | cut -d: -f1)"
object_initializer_count="$(grep -c '^let __init_sameModuleObject = sameModuleObject := ' "$source_file" || true)"
if [ "$object_type_line" -ge "$object_declaration_line" ] || [ "$object_declaration_line" -ge "$worker_line" ] || [ "$object_initializer_count" -ne 1 ]; then
	echo "The class-valued static cell must be declared once after its carrier type and before SameModuleWorker values" >&2
	exit 1
fi

if ! grep -q '^let omitted = ref (0 : int)$' "$external_source_file"; then
	echo "An omitted exact Int static must use the selected int carrier and zero default" >&2
	exit 1
fi
if ! grep -q '^let omittedBool = ref (false : bool)$' "$external_source_file"; then
	echo "An omitted exact Bool static must use the selected bool carrier and false default" >&2
	exit 1
fi
if ! grep -q '^let omittedNullableInt = ref (HxRuntime.hx_null : Obj.t)$' "$external_source_file"; then
	echo "An omitted exact Null<Int> static must use direct HxRuntime.hx_null on Obj.t" >&2
	exit 1
fi
if ! grep -q '^let omittedNullableBool = ref (HxRuntime.hx_null : Obj.t)$' "$external_source_file"; then
	echo "An omitted exact Null<Bool> static must use direct HxRuntime.hx_null on Obj.t" >&2
	exit 1
fi
if ! grep -q '^let omittedString = ref (HxString.hx_null_string : string)$' "$external_source_file"; then
	echo "An omitted exact String static must use the sealed string carrier and runtime-null default" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decision = report.representations.find(item => item.id === 'representation:Int:static-field')
const boolDecision = report.representations.find(item => item.id === 'representation:Bool:static-field')
const nullableIntDecision = report.representations.find(item => item.id === 'representation:Null<Int>:static-field')
const nullableBoolDecision = report.representations.find(item => item.id === 'representation:Null<Bool>:static-field')
const stringDecision = report.representations.find(item => item.id === 'representation:String:static-field')
const external = report.staticStorage.find(item => item.key === 'ExternalHolder::ExternalHolder::omitted')
const externalBool = report.staticStorage.find(item => item.key === 'ExternalHolder::ExternalHolder::omittedBool')
const externalNullableInt = report.staticStorage.find(item => item.key === 'ExternalHolder::ExternalHolder::omittedNullableInt')
const externalNullableBool = report.staticStorage.find(item => item.key === 'ExternalHolder::ExternalHolder::omittedNullableBool')
const externalString = report.staticStorage.find(item => item.key === 'ExternalHolder::ExternalHolder::omittedString')
const sameModuleBool = report.staticStorage.find(item => item.key === 'Main::Main::sameModuleBool')
const sameModuleNullableInt = report.staticStorage.find(item => item.key === 'Main::Main::sameModuleNullableInt')
const boolAssignment = report.plans.find(item =>
	item.nodeKind === 'static-simple-assignment'
	&& item.semanticTypeId === 'Bool'
	&& item.carrierTypeId === 'bool'
	&& item.place?.representationId === boolDecision?.id)
const stringAssignment = report.plans.find(item =>
	item.nodeKind === 'static-simple-assignment'
	&& item.semanticTypeId === 'String'
	&& item.carrierTypeId === 'string'
	&& item.place?.fieldName === 'omittedString'
	&& item.place?.representationId === stringDecision?.id)
if (!decision
	|| decision.carrierTypeId !== 'int'
	|| decision.implicitDefaultPolicy !== 'exact-int-zero'
	|| !external
	|| external.representationId !== decision.id) {
	throw new Error('the lowering report did not preserve the exact Int static carrier/default decision')
}
if (!boolDecision
	|| boolDecision.carrierTypeId !== 'bool'
	|| boolDecision.implicitDefaultPolicy !== 'exact-bool-false'
	|| !externalBool
	|| externalBool.representationId !== boolDecision.id
	|| !sameModuleBool
	|| sameModuleBool.declarationSite !== 'module-prelude'
	|| sameModuleBool.representationId !== boolDecision.id
	|| !boolAssignment) {
	throw new Error('the lowering report did not preserve the exact Bool static carrier/default/simple-assignment decision')
}
if (!nullableIntDecision
	|| nullableIntDecision.carrierTypeId !== 'Obj.t'
	|| nullableIntDecision.implicitDefaultPolicy !== 'runtime-null-sentinel'
	|| !nullableBoolDecision
	|| nullableBoolDecision.carrierTypeId !== 'Obj.t'
	|| nullableBoolDecision.implicitDefaultPolicy !== 'runtime-null-sentinel'
	|| !externalNullableInt
	|| externalNullableInt.representationId !== nullableIntDecision.id
	|| !externalNullableBool
	|| externalNullableBool.representationId !== nullableBoolDecision.id
	|| !sameModuleNullableInt
	|| sameModuleNullableInt.declarationSite !== 'module-prelude'
	|| sameModuleNullableInt.representationId !== nullableIntDecision.id) {
	throw new Error('the lowering report did not preserve exact nullable primitive static carrier/default decisions')
}
if (!stringDecision
	|| stringDecision.carrierTypeId !== 'string'
	|| stringDecision.nullPolicy !== 'runtime-sentinel'
	|| stringDecision.boxingPolicy !== 'nullable-string-carrier'
	|| stringDecision.implicitDefaultPolicy !== 'runtime-null-sentinel'
	|| stringDecision.proof?.id !== 'nullable-string-runtime-sentinel-carrier-v1'
	|| !externalString
	|| externalString.representationId !== stringDecision.id
	|| !stringAssignment
	|| stringAssignment.conversion !== 'identity') {
	throw new Error('the lowering report did not preserve the exact String static carrier/default/simple-assignment decision')
}
NODE

echo "STATIC_STORAGE_SOURCE_SHAPE:PASS"
