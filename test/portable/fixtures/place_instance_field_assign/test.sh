#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated instance-field source or lowering report" >&2
	exit 1
fi

if ! grep -q '^type holder_t = .*mutable value : int' "$source_file"; then
	echo "Holder.value must use the exact Int field carrier selected before emission" >&2
	exit 1
fi
if ! grep -q 'value = 0.*: holder_t' "$source_file"; then
	echo "Holder.value must use the exact Int zero default selected before emission" >&2
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
if (!decision
	|| decision.carrierTypeId !== 'int'
	|| decision.implicitDefaultPolicy !== 'exact-int-zero') {
	throw new Error('the lowering report did not preserve the exact Int instance-field carrier/default decision')
}
NODE

echo "INSTANCE_FIELD_REPRESENTATION_SOURCE_SHAPE:PASS"
