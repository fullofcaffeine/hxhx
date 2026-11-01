#!/usr/bin/env bash
set -euo pipefail

# Checks the lowering decisions behind expected.stdout, then checks the one
# nullable Map shape that reflaxe.ocaml rejects with a source-level error.
node <<'NODE'
const fs = require('fs')

const report = JSON.parse(fs.readFileSync('out/ocaml_lowering_report.json', 'utf8'))
if (report.schemaVersion !== 95 || report.iMapInterfaceModel !== 'typed-imap-interface-adapter-v7')
	throw new Error('unexpected lowering report schema or IMap model')

// Concrete-key nullable Map fields, method results, and anonymous fields keep
// raw Map storage after a single null check. This includes object keys.
const aliasSources = new Set(report.iMapStorageAliases.map(alias => alias.sourceSemanticTypeId))
for (const source of ['Null<Map<String, String>>', 'Null<Map<Int, Int>>', 'Null<Map<Int, String>>', 'Null<Map<String, Int>>', 'Null<Map<Key, Int>>']) {
	if (!aliasSources.has(source))
		throw new Error(`no checked storage alias for ${source}`)
}
if (report.iMapStorageAliases.some(alias => alias.nullPolicy !== 'check-null-and-unbox' || alias.sourceCarrierTypeId !== 'Obj.t'))
	throw new Error('a nullable Map storage alias skipped its null check')

const conversions = report.iMapInterfaceConversions
const roles = conversion => conversion.runtimeUseOccurrences.map(use => use.role)
const throwing = conversion => roles(conversion)[0] === 'check-null' && roles(conversion)[1] === 'throw-null-access'
const keepsNull = conversion => roles(conversion)[0] === 'check-null' && !roles(conversion).includes('throw-null-access')

// Generic nullable Map fields use Haxe's single-use expansion and throw Null
// Access at its initializer when the Map is null.
const generic = conversions.filter(conversion => conversion.sourceSemanticTypeId === 'Null<Map<Box.K, Box.V>>')
if (generic.length !== 6
	|| generic.some(conversion => conversion.role !== 'receiver-local-initializer'
		|| conversion.sourceCarrierTypeId !== 'Obj.t'
		|| !throwing(conversion)
		|| !conversion.runtimeCapabilities.includes('haxe-runtime-core'))) {
	throw new Error('generic nullable Map receivers did not select the checked throwing conversion')
}

// IMap arguments (String and Int keys) and explicit IMap locals that are not
// method receivers keep null as null.
const concrete = conversions.filter(conversion => conversion.sourceSemanticTypeId !== 'Null<Map<Box.K, Box.V>>')
const argumentKeys = new Set(concrete.filter(conversion => conversion.role === 'call-argument').map(conversion => conversion.keySemanticTypeId))
if (concrete.length !== 6
	|| concrete.some(conversion => !['call-argument', 'local-initializer'].includes(conversion.role) || !keepsNull(conversion))
	|| concrete.filter(conversion => conversion.role === 'local-initializer').length !== 2
	|| !argumentKeys.has('String')
	|| !argumentKeys.has('Int')) {
	throw new Error('a nullable Map IMap argument or non-receiver IMap local did not keep null as null')
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

# Two valid Haxe shapes still stop with a named error at the user's source
# position, never with a plan invariant or a compiler-generated local name.
negative="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-ocaml-nullable-imap-local.XXXXXX")"
trap 'rm -rf "$negative"' EXIT

# expect_error <case> <line> <pattern>: compile cases/<case>/Main.hx and require
# the error at Main.hx:<line> to match <pattern>.
expect_error() {
	local name="$1" line="$2" pattern="$3" dir="$negative/$1"
	if haxe -cp "$dir" -main Main -lib reflaxe.ocaml -D ocaml_output="$dir/out" -D ocaml_no_build >"$dir/log" 2>&1; then
		echo "negative case $name compiled without its documented error" >&2
		exit 1
	fi
	if ! grep -q "Main.hx:$line: characters .*$pattern" "$dir/log" \
		|| grep -q 'plan-invariant' "$dir/log" \
		|| grep -q '"this1"' "$dir/log"; then
		echo "negative case $name lacks its source position or message" >&2
		cat "$dir/log" >&2
		exit 1
	fi
}

# An IMap local that may hold null and is called later, not immediately.
# Haxe keeps null in the local and fails only if the call runs. The target does
# not check a null IMap receiver yet, so the call is rejected.
mkdir -p "$negative/delayed_call"
cat >"$negative/delayed_call/Main.hx" <<'HX'
class Main {
	static var calls = 0;
	static function make():Null<Map<String, Int>> { calls++; return null; }
	static function main():Void {
		final view:haxe.Constraints.IMap<String, Int> = make();
		if (calls > 100)
			view.get("x");
		Sys.println("condView=ok");
	}
}
HX
expect_error delayed_call 7 '\[ocaml-imap-interface:nullable-receiver-unsupported\]: this call uses IMap local "view"'

# A nullable Map produced by an expression whose storage is not proven, here a
# conditional between two static fields.
mkdir -p "$negative/unproven_producer"
cat >"$negative/unproven_producer/Main.hx" <<'HX'
class Main {
	static var a:Null<Map<String, Int>> = ["k" => 1];
	static var b:Null<Map<String, Int>> = null;
	static function main():Void {
		final pick = Sys.args().length == 0;
		Sys.println((pick ? a : b).get("k"));
	}
}
HX
expect_error unproven_producer 6 '\[ocaml-imap-interface:unproven-nullable-producer\]: this Null<\(haxe\.ds\.\)*Map<String, Int>> value is not proven to be stored as Obj.t'

echo "NULLABLE_MAP_RECEIVER_SHAPES:PASS"
