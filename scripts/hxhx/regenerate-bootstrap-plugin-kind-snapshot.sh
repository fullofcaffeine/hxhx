#!/usr/bin/env bash
set -euo pipefail

# Refresh the bootstrap snapshot units that encode backend plugin manifest kinds.
#
# Why
# - Full hxhx bootstrap regeneration can be expensive in some environments.
# - Kind-contract drift in these units is a release blocker because it causes
#   source-vs-bootstrap behavioral mismatch.
#
# What
# - Compile a tiny harness that references:
#   - backend.plugin.BackendPluginManifestParser
#   - hxhx.BackendPluginManifestResolver
# - Emit OCaml with stage0 haxe + reflaxe.ocaml.
# - Copy only the two generated snapshot units into packages/hxhx/bootstrap_out.
#
# Notes
# - This script is intentionally narrow; it is not a replacement for full
#   bootstrap regeneration when broader snapshot updates are required.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
BOOTSTRAP_OUT="$ROOT/packages/hxhx/bootstrap_out"

if [ ! -d "$BOOTSTRAP_OUT" ]; then
	echo "Missing bootstrap output directory: $BOOTSTRAP_OUT" >&2
	exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hxhx-bootstrap-kind-refresh.XXXXXX")"
cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_DIR/BootstrapKindParityRegenMain.hx" <<'EOF'
import backend.plugin.BackendPluginManifest;
import backend.plugin.BackendPluginManifestParser;
import hxhx.BackendPluginManifestResolver;

class BootstrapKindParityRegenMain {
	static function linkedManifest():String {
		return haxe.Json.stringify({
			schemaVersion: 1,
			pluginId: "bootstrap-kind-regen",
			pluginVersion: "0.0.0",
			backend: {
				kind: "linked-provider",
				entry: "backend.js.JsBackend",
				targetIds: ["js-native"],
				priority: 0,
				description: "targeted bootstrap regen harness"
			}
		});
	}

	static function main():Void {
		final raw = linkedManifest();
		final manifest:BackendPluginManifest = BackendPluginManifestParser.parse(raw, "fixture://bootstrap-kind-regen");
		final providers = BackendPluginManifestResolver.providerTypeNamesForManifest(manifest, "fixture://bootstrap-kind-regen");
		if (providers.length != 1 || providers[0] != "backend.js.JsBackend") {
			throw "unexpected provider resolution in bootstrap kind regen harness";
		}
		Sys.println("bootstrap-kind-regen=ok");
	}
}
EOF

OUT_DIR="$TMP_DIR/out"
mkdir -p "$OUT_DIR"

echo "== Targeted bootstrap kind refresh: compiling harness via $HAXE_BIN"
"$HAXE_BIN" \
	-cp "$ROOT/packages/hxhx/src" \
	-cp "$ROOT/packages/hxhx-core/src" \
	-cp "$TMP_DIR" \
	-main BootstrapKindParityRegenMain \
	-lib reflaxe.ocaml \
	-D no-traces \
	-D no_traces \
	-D reflaxe_ocaml \
	-D hih_native_parser \
	-D ocaml_emit_only \
	-D "ocaml_output=$OUT_DIR"

PARSER_FILE="$OUT_DIR/backend_plugin_BackendPluginManifestParser.ml"
RESOLVER_FILE="$OUT_DIR/hxhx_BackendPluginManifestResolver.ml"

if [ ! -f "$PARSER_FILE" ]; then
	echo "Missing generated parser file: $PARSER_FILE" >&2
	exit 1
fi
if [ ! -f "$RESOLVER_FILE" ]; then
	echo "Missing generated resolver file: $RESOLVER_FILE" >&2
	exit 1
fi

echo "== Updating bootstrap snapshot units"
cp "$PARSER_FILE" "$BOOTSTRAP_OUT/backend_plugin_BackendPluginManifestParser.ml"
cp "$RESOLVER_FILE" "$BOOTSTRAP_OUT/hxhx_BackendPluginManifestResolver.ml"

echo "== Done:"
echo "   - $BOOTSTRAP_OUT/backend_plugin_BackendPluginManifestParser.ml"
echo "   - $BOOTSTRAP_OUT/hxhx_BackendPluginManifestResolver.ml"
