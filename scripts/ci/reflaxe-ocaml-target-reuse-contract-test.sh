#!/usr/bin/env bash
set -euo pipefail

# Proves both the plain target contract and its placement in real Reflaxe target
# startup. This observation never skips target work or publishes cached output.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/test/portable/fixtures/call_exact_int_static"
PROBE_SOURCE="$ROOT/test/reflaxe_ocaml_target_reuse/src"
OUTPUT_NAME="out_target_reuse_contract_$$"

cleanup() {
	if [[ -d "$FIXTURE/$OUTPUT_NAME" ]]; then
		find "$FIXTURE/$OUTPUT_NAME" -depth -delete
	fi
}
trap cleanup EXIT

cd "$ROOT"
haxe \
	-cp packages/reflaxe.ocaml/src \
	-cp "$PROBE_SOURCE" \
	-lib reflaxe \
	-D reflaxe_runtime \
	--macro 'nullSafety("reflaxe.ocaml")' \
	--run TargetReuseContractFixture

cd "$FIXTURE"
haxe build.hxml \
	-cp "$PROBE_SOURCE" \
	--macro 'TargetReuseProbeFixture.install()' \
	-D ocaml_no_build \
	-D "ocaml_output=$OUTPUT_NAME"

echo "REFLAXE_OCAML_TARGET_REUSE_PROBE:PASS"
