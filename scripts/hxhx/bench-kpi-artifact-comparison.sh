#!/usr/bin/env bash
# Build a native hxhx and compare it with an existing bytecode KPI report.
# The caller chooses the output directory so the complete diagnostic bundle can
# be uploaded even when native evidence is unavailable or incomparable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
BYTECODE_SOURCE_DIR="${HXHX_KPI_BYTECODE_REPORT_DIR:-}"
COMPARISON_DIR="${HXHX_KPI_COMPARISON_DIR:-$ROOT/.hxhx/bench/kpi-artifact-comparison}"
BYTECODE_DIR="$COMPARISON_DIR/bytecode"
NATIVE_DIR="$COMPARISON_DIR/native"
COMPARISON_JSON="$COMPARISON_DIR/comparison.json"

if [ -z "$BYTECODE_SOURCE_DIR" ] || [ ! -f "$BYTECODE_SOURCE_DIR/report.json" ]; then
	echo "Set HXHX_KPI_BYTECODE_REPORT_DIR to an existing bytecode KPI report directory." >&2
	exit 2
fi

cd "$ROOT"
rm -rf "$COMPARISON_DIR"
mkdir -p "$BYTECODE_DIR" "$NATIVE_DIR"
cp -R "$BYTECODE_SOURCE_DIR"/. "$BYTECODE_DIR"/

native_bin=""
if ! native_bin="$(HXHX_BOOTSTRAP_PREFER_NATIVE=1 HXHX_STAGE0_OCAML_BUILD=native HAXE_BIN="$HAXE_BIN" bash scripts/hxhx/build-hxhx.sh | tail -n 1)"; then
	echo "Native hxhx build failed; no native comparison is available." >&2
	exit 1
fi
if [ -z "$native_bin" ] || [ ! -x "$native_bin" ]; then
	echo "Native hxhx build did not return an executable path." >&2
	exit 1
fi

HXHX_BIN="$native_bin" HXHX_KPI_REPORT_DIR="$NATIVE_DIR" npm run hxhx:bench:kpi
node scripts/ci/hxhx-kpi-report-validator.js --report "$NATIVE_DIR/report.json"
node scripts/ci/hxhx-kpi-artifact-comparison.js \
	--bytecode-report "$BYTECODE_DIR/report.json" \
	--native-report "$NATIVE_DIR/report.json" \
	--json-out "$COMPARISON_JSON"

echo "Bytecode/native KPI comparison: $COMPARISON_JSON"
