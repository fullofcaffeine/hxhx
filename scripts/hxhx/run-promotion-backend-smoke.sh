#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROMOTE_SCRIPT="$ROOT/scripts/hxhx/promote-backend-plugin.sh"
OCAMLOPT_WRAPPER="$ROOT/scripts/hxhx/ocamlopt-with-threads.sh"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlopt >/dev/null 2>&1; then
  echo "Skipping promotion backend smoke: dune/ocamlopt not found on PATH."
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Skipping promotion backend smoke: node not found on PATH."
  exit 0
fi

if [ ! -x "$PROMOTE_SCRIPT" ]; then
  echo "Missing executable promote script: $PROMOTE_SCRIPT" >&2
  exit 1
fi

if [ -z "${OCAMLOPT:-}" ] && [ -x "$OCAMLOPT_WRAPPER" ]; then
  export OCAMLOPT="$OCAMLOPT_WRAPPER"
fi

HXHX_BIN_RESOLVED="${HXHX_BIN:-}"
if [ -z "$HXHX_BIN_RESOLVED" ] || [ ! -x "$HXHX_BIN_RESOLVED" ]; then
  HXHX_BIN_RESOLVED="$(bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi
if [ ! -x "$HXHX_BIN_RESOLVED" ]; then
  echo "Failed to resolve executable hxhx binary: $HXHX_BIN_RESOLVED" >&2
  exit 2
fi

tmp_root="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

promoted_out="$tmp_root/promoted"
artifact_ext="cmxs"
case "$HXHX_BIN_RESOLVED" in
  *.bc)
    artifact_ext="cma"
    ;;
esac

bash "$PROMOTE_SCRIPT" \
  --plugin-id fixture.promoted.backend.plugin \
  --plugin-version 0.1.0 \
  --provider-type backend.js.JsBackend \
  --target-id js-native \
  --artifact-ext "$artifact_ext" \
  --out-dir "$promoted_out"

manifest="$promoted_out/backend-plugin.json"
artifact="$promoted_out/plugins/fixture_promoted_backend_plugin.${artifact_ext}"
if [ ! -f "$manifest" ] || [ ! -f "$artifact" ]; then
  echo "promotion backend smoke: missing promoted artifacts" >&2
  exit 2
fi

fixture_src="$tmp_root/src"
mkdir -p "$fixture_src"
cat >"$fixture_src/Main.hx" <<'HX'
class Main {
	static function main() {
		var sum = 0;
		for (i in 1...4)
			sum += i;
		Sys.println("sum=" + sum);
	}
}
HX

out_dir="$tmp_root/out"
mkdir -p "$out_dir"

set +e
compile_output="$(
  HXHX_FORBID_STAGE0=1 \
    HXHX_TRACE_BACKEND_SELECTION=1 \
    HXHX_TRACE_BACKEND_PROVIDERS=1 \
    "$HXHX_BIN_RESOLVED" \
      --js "$out_dir/main.js" \
      --hxhx-no-run \
      -cp "$fixture_src" \
      -main Main \
      --hxhx-out "$out_dir" \
      -D "hxhx_backend_provider=backend.js.JsBackend" \
      -D "hxhx_backend_plugin_manifest=$manifest" 2>&1
)"
compile_code="$?"
set -e
printf '%s\n' "$compile_output"
if [ "$compile_code" -ne 0 ]; then
  echo "promotion backend smoke: stage3 compile failed" >&2
  exit "$compile_code"
fi
printf '%s\n' "$compile_output" | grep -q '^backend_selected_impl=provider/js-native-wrapper$'

node_output="$(node "$out_dir/main.js")"
printf '%s\n' "$node_output"
printf '%s\n' "$node_output" | grep -q '^sum=6$'

echo "promotion_manifest=$manifest"
echo "promotion_artifact=$artifact"
echo "PROMOTION_BACKEND_SMOKE:PASS"
