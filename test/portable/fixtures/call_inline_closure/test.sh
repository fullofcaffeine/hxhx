#!/usr/bin/env bash
set -euo pipefail

main_source="out/Main.ml"
report_file="out/ocaml_lowering_report.json"
if [ ! -f "$main_source" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated inline-closure source or lowering report" >&2
	exit 1
fi

node - "$main_source" "$report_file" <<'NODE'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const report = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'))
if (report.schemaVersion !== 72 || report.callModel !== 'typed-ocaml-directional-call-boundary-v21') {
	throw new Error('expected the current typed-call report model')
}

const valueStart = source.indexOf('let inlineValueCase =')
const voidStart = source.indexOf('let inlineVoidCase =')
const mainStart = source.indexOf('let main =')
if (valueStart < 0 || voidStart <= valueStart || mainStart <= voidStart) {
	throw new Error('could not isolate generated inline-closure cases')
}
const valueBody = source.slice(valueStart, voidStart)
const voidBody = source.slice(voidStart, mainStart)
if (!/let offset = 1 in let value = argument \(\) in/.test(valueBody)
	|| !/record __call_arg_[0-9]+/.test(valueBody)
	|| !/HxInt\.add offset value/.test(valueBody)) {
	throw new Error('the value closure did not preserve capture and argument-before-body order')
}
if (!/let value = argument \(\) in/.test(voidBody)
	|| !/record __call_arg_[0-9]+/.test(voidBody)
	|| !/if value <> 41/.test(voidBody)) {
	throw new Error('the Void closure did not preserve argument-before-body order')
}
if (/__call_callee_|fun \(value/.test(valueBody + voidBody)) {
	throw new Error('an immediate closure unexpectedly survived as a target call')
}
if ((report.calls ?? []).some(call =>
	call.kind === 'typed-function-value'
	&& call.source?.file?.endsWith('reflaxe_ocaml_inline_closure_call_seed/src/Main.hx'))) {
	throw new Error('the report invented a function-value call after Haxe normalized the immediate closure')
}
NODE

first_report="$(mktemp)"
inspection_report="$(mktemp)"
trap 'rm -f "$first_report" "$inspection_report"' EXIT
cp "$report_file" "$first_report"
haxe build.hxml -D ocaml_build=native
if ! cmp -s "$first_report" "$report_file"; then
	echo "The inline-closure report changed across identical compiler runs" >&2
	exit 1
fi

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
(
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output out --require-lowering --json
) >"$inspection_report"
node - "$inspection_report" <<'NODE'
const fs = require('fs')
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
if (!report.summary?.valid) {
	throw new Error('reflaxe.ocaml inspection rejected the inline-closure output')
}
NODE

echo "INLINE_CLOSURE_FRONTEND_NORMALIZATION:PASS"
