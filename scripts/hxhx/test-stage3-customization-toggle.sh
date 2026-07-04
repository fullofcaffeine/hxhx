#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$ROOT/.tmp/stage3-customization-toggle"
SRC_DIR="$TMP_DIR/src"
BASE_OUT="$TMP_DIR/baseline.stdout"
ENABLED_OUT="$TMP_DIR/enabled.stdout"
ENABLED_NORMALIZED="$TMP_DIR/enabled.normalized.stdout"
UNKNOWN_OUT="$TMP_DIR/unknown.stdout"
STRICT_OUT="$TMP_DIR/strict.stdout"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

rm -rf "$TMP_DIR"
mkdir -p "$SRC_DIR"

cat >"$SRC_DIR/Main.hx" <<'HX'
class Main {
  static function main():Void {
    trace("customization-toggle");
  }
}
HX

HXHX_BIN_RESOLVED="$(bash "$ROOT/scripts/hxhx/current-source-hxhx-bin.sh" | tail -n 1)"
if [ -z "$HXHX_BIN_RESOLVED" ] || { [ ! -x "$HXHX_BIN_RESOLVED" ] && [[ "$HXHX_BIN_RESOLVED" != *.bc ]]; }; then
  echo "Missing current-source hxhx binary: $HXHX_BIN_RESOLVED" >&2
  exit 1
fi

if [[ "$HXHX_BIN_RESOLVED" == *.bc ]]; then
  HXHX_CMD=(ocamlrun "$HXHX_BIN_RESOLVED")
else
  HXHX_CMD=("$HXHX_BIN_RESOLVED")
fi

HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used "${HXHX_CMD[@]}" \
  --ocaml \
  --hxhx-no-emit \
  -cp "$SRC_DIR" \
  -main Main \
  --hxhx-out "$TMP_DIR/out_baseline" \
  >"$BASE_OUT"

grep -q "^stage3=no_emit_ok$" "$BASE_OUT"
if grep -q "^hxhx_customization" "$BASE_OUT"; then
  echo "Disabled baseline unexpectedly emitted customization markers." >&2
  cat "$BASE_OUT" >&2
  exit 1
fi

HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used "${HXHX_CMD[@]}" \
  --ocaml \
  --hxhx-customization report-typed-summary \
  --hxhx-no-emit \
  -cp "$SRC_DIR" \
  -main Main \
  --hxhx-out "$TMP_DIR/out_enabled" \
  >"$ENABLED_OUT"

grep -q "^stage3=no_emit_ok$" "$ENABLED_OUT"
grep -q "^hxhx_customization\\[report-typed-summary\\]=enabled$" "$ENABLED_OUT"
grep -q "^hxhx_customization_report\\[report-typed-summary\\]\\.phase=no_emit$" "$ENABLED_OUT"
grep -q "^hxhx_customization_report\\[report-typed-summary\\]\\.backend=ocaml-stage3$" "$ENABLED_OUT"
grep -q "^hxhx_customization_report\\[report-typed-summary\\]\\.typed_modules=1$" "$ENABLED_OUT"
grep -q "^hxhx_customization_report\\[report-typed-summary\\]\\.header_only_modules=0$" "$ENABLED_OUT"
grep -q "^hxhx_customization_report\\[report-typed-summary\\]\\.unsupported_exprs_total=0$" "$ENABLED_OUT"
grep -q "^hxhx_customization_report\\[report-typed-summary\\]\\.unsupported_files=0$" "$ENABLED_OUT"

grep -v "^hxhx_customization" "$ENABLED_OUT" >"$ENABLED_NORMALIZED"
if ! diff -u "$BASE_OUT" "$ENABLED_NORMALIZED"; then
  echo "Enabled customization changed baseline Stage3 output beyond customization report lines." >&2
  exit 1
fi

if HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used "${HXHX_CMD[@]}" \
  --ocaml \
  --hxhx-customization unknown-customization \
  --hxhx-no-emit \
  -cp "$SRC_DIR" \
  -main Main \
  --hxhx-out "$TMP_DIR/out_unknown" \
  >"$UNKNOWN_OUT" 2>&1; then
  echo "Unknown customization ID unexpectedly succeeded." >&2
  cat "$UNKNOWN_OUT" >&2
  exit 1
fi
grep -q "unsupported --hxhx-customization: unknown-customization" "$UNKNOWN_OUT"

if "${HXHX_CMD[@]}" \
  --hxhx-strict-cli \
  --hxhx-customization report-typed-summary \
  --version \
  >"$STRICT_OUT" 2>&1; then
  echo "Strict CLI unexpectedly accepted --hxhx-customization." >&2
  cat "$STRICT_OUT" >&2
  exit 1
fi
grep -q "strict CLI mode rejects non-upstream flag: --hxhx-customization" "$STRICT_OUT"

echo "STAGE3_CUSTOMIZATION_TOGGLE:PASS"
