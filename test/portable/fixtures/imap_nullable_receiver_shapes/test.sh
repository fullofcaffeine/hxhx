#!/usr/bin/env bash
set -euo pipefail

# Checks the lowering decisions behind expected.stdout, then checks the one
# nullable Map shape that reflaxe.ocaml rejects with a source-level error.
node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 95 || report.iMapInterfaceModel !== 'typed-imap-interface-adapter-v7')
	throw new Error('unexpected lowering report schema or IMap model')

// Concrete-key nullable Map fields, call results, and anonymous fields keep raw
// Map storage after a single null check.
const aliasSources = new Set(report.iMapStorageAliases.map(alias => alias.sourceSemanticTypeId))
for (const source of ['Null<Map<String, String>>', 'Null<Map<Int, Int>>', 'Null<Map<Int, String>>', 'Null<Map<String, Int>>']) {
	if (!aliasSources.has(source))
		throw new Error(`no checked storage alias for ${source}`)
}
if (report.iMapStorageAliases.some(alias => alias.nullPolicy !== 'check-null-and-unbox' || alias.sourceCarrierTypeId !== 'Obj.t'))
	throw new Error('a nullable Map storage alias skipped its null check')

// Generic nullable Map fields convert to IMap and throw Null Access on null.
// A nullable Map passed to an IMap parameter keeps null as null.
const conversions = report.iMapInterfaceConversions
const generic = conversions.filter(conversion => conversion.sourceSemanticTypeId === 'Null<Map<Box.K, Box.V>>')
const argument = conversions.filter(conversion => conversion.sourceSemanticTypeId === 'Null<Map<String, Int>>')
const roles = conversion => conversion.runtimeUseOccurrences.map(use => use.role)
if (generic.length !== 6
	|| generic.some(conversion => conversion.role !== 'local-initializer'
		|| conversion.sourceCarrierTypeId !== 'Obj.t'
		|| roles(conversion)[0] !== 'check-null'
		|| roles(conversion)[1] !== 'throw-null-access'
		|| !conversion.runtimeCapabilities.includes('haxe-runtime-core'))) {
	throw new Error('generic nullable Map receivers did not select the checked throwing conversion')
}
if (argument.length !== 2
	|| argument.some(conversion => conversion.role !== 'call-argument'
		|| roles(conversion)[0] !== 'check-null'
		|| roles(conversion).includes('throw-null-access'))) {
	throw new Error('a nullable Map IMap argument did not keep null as null')
}

const generated = fs.readFileSync('out/Main.ml', 'utf8')
if (!generated.includes('if HxRuntime.is_null __nullable_imap_source_')
	|| !generated.includes('if HxRuntime.is_null __nullable_standard_map_'))
	throw new Error('generated OCaml lacks the planned nullable Map checks')
NODE

repo_root="$(cd ../../../.. && pwd)"
fixture_root="$PWD"
(
	cd "$repo_root"
	haxe -cp packages/reflaxe.ocaml/src \
		--macro 'nullSafety("reflaxe.ocaml")' \
		--run reflaxe.ocaml.tooling.ReflaxeOcamlRun \
		inspect --project "$fixture_root" --output out --require-lowering --json
) >/dev/null

# A nullable Map stored in an IMap local that is compared with null is valid
# Haxe. The target cannot keep that null IMap safely yet, so it must stop with
# a named error at the initializer instead of a plan invariant.
negative="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-ocaml-nullable-imap-local.XXXXXX")"
trap 'rm -rf "$negative"' EXIT
cat >"$negative/Main.hx" <<'HX'
class Main {
	static function make():Null<Map<String, Int>>
		return null;

	static function main():Void {
		var view:haxe.Constraints.IMap<String, Int> = make();
		Sys.println(view == null);
	}
}
HX
if haxe -cp "$negative" -main Main -lib reflaxe.ocaml -D ocaml_output="$negative/out" -D ocaml_no_build >"$negative/log" 2>&1; then
	echo "a nullable Map in a compared IMap local compiled without its documented error" >&2
	exit 1
fi
if ! grep -q 'Main.hx:6: characters .*\[ocaml-imap-interface:nullable-local-unsupported\]: Null<Map<String, Int>> is stored in IMap local "view"' "$negative/log" \
	|| grep -q 'plan-invariant' "$negative/log"; then
	echo "the nullable IMap local error is missing its source position or message" >&2
	cat "$negative/log" >&2
	exit 1
fi

echo "NULLABLE_MAP_RECEIVER_SHAPES:PASS"
