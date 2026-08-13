#!/usr/bin/env bash
set -euo pipefail

source_file="out/Main.ml"
report_file="out/ocaml_lowering_report.json"

if [ ! -f "$source_file" ] || [ ! -f "$report_file" ]; then
	echo "Missing generated entrypoint source or lowering report" >&2
	exit 1
fi

if ! grep -Eq 'ignore \(GeneratedEntrypoint\.init \(\)\);' "$source_file" \
	|| ! grep -Fq 'HxRuntime.hx_null' "$source_file"; then
	echo "The Dynamic local did not run the sealed Void call and then produce Haxe null" >&2
	exit 1
fi

node - "$report_file" <<'NODE'
const fs = require('fs');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const calls = report.calls ?? [];
const matches = calls.filter(call =>
	call.calleeId === 'GeneratedEntrypoint|GeneratedEntrypoint::init'
	&& call.resultKind === 'effect-only-void'
	&& call.resultMaterialization === 'untyped-void-as-dynamic-null');
if (matches.length !== 1) {
	throw new Error(`expected one sealed effect-only generated entrypoint call, got ${matches.length}`);
}
NODE

negative_log="$(mktemp)"
if haxe negative.hxml >"$negative_log" 2>&1; then
	echo "An unplanned generated entrypoint call unexpectedly reached target syntax" >&2
	exit 1
fi
if ! grep -Fq '[ocaml-call:plan-invariant]' "$negative_log" \
	|| ! grep -Fq 'reached syntax without its sealed occurrence plan' "$negative_log"; then
	echo "The unplanned generated entrypoint did not report the stable call-plan diagnostic" >&2
	cat "$negative_log" >&2
	exit 1
fi
if [ -f negative-out/UnplannedGeneratedEntrypoint.ml ]; then
	echo "The unplanned generated entrypoint wrote OCaml output" >&2
	exit 1
fi
