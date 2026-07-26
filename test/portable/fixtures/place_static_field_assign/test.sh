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

node - "$report_file" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const decision = report.representations.find(item => item.id === 'representation:Int:static-field')
const external = report.staticStorage.find(item => item.key === 'ExternalHolder::ExternalHolder::omitted')
if (!decision
	|| decision.carrierTypeId !== 'int'
	|| decision.implicitDefaultPolicy !== 'exact-int-zero'
	|| !external
	|| external.representationId !== decision.id) {
	throw new Error('the lowering report did not preserve the exact Int static carrier/default decision')
}
NODE

echo "STATIC_STORAGE_SOURCE_SHAPE:PASS"
