#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$ROOT/.tmp/m14_stage3_sys_stdio_intrinsics"
SRC_DIR="$TMP_DIR/src"
OUT_DIR="$TMP_DIR/out"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

rm -rf "$TMP_DIR"
mkdir -p "$SRC_DIR"

cat >"$SRC_DIR/Main.hx" <<'HX'
class Main {
  static function main():Void {
    final input = Sys.stdin();
    final out = Sys.stdout();
    final err = Sys.stderr();
    Sys.stdout().writeString("stdio-ok\n");
    Sys.stdout().flush();
    Sys.stderr().flush();
    if (input == null) {
      throw "stdin-null";
    }
  }
}
HX

HXHX_BIN_RESOLVED="${HXHX_BIN:-}"
if [ -z "$HXHX_BIN_RESOLVED" ]; then
  HXHX_BIN_RESOLVED="$(HXHX_FORBID_STAGE0=1 HXHX_FORCE_STAGE0=0 bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi

if [ ! -x "$HXHX_BIN_RESOLVED" ] && [[ "$HXHX_BIN_RESOLVED" != *.bc ]]; then
  echo "Missing executable hxhx binary: $HXHX_BIN_RESOLVED" >&2
  exit 1
fi

if [[ "$HXHX_BIN_RESOLVED" == *.bc ]]; then
  HXHX_CMD=(ocamlrun "$HXHX_BIN_RESOLVED")
else
  HXHX_CMD=("$HXHX_BIN_RESOLVED")
fi

HXHX_FORBID_STAGE0=1 "${HXHX_CMD[@]}" \
  --ocaml \
  --hxhx-emit-full-bodies \
  --hxhx-no-run \
  -cp "$SRC_DIR" \
  -main Main \
  --hxhx-out "$OUT_DIR"

MAIN_ML="$OUT_DIR/Main.ml"
if [ ! -f "$MAIN_ML" ]; then
  echo "Missing generated Main.ml at $MAIN_ML" >&2
  exit 1
fi

grep -q "Sys_io_Stdio.stdin ()" "$MAIN_ML"
grep -q "Sys_io_Stdio.stdout ()" "$MAIN_ML"
grep -q "Sys_io_Stdio.stderr ()" "$MAIN_ML"
if grep -q "Sys.stdin ()" "$MAIN_ML"; then
  echo "Unexpected raw Sys.stdin() emission in $MAIN_ML" >&2
  exit 1
fi

if [ ! -x "$OUT_DIR/out.exe" ]; then
  echo "Missing emitted executable at $OUT_DIR/out.exe" >&2
  exit 1
fi
"$OUT_DIR/out.exe" >"$TMP_DIR/stdout.log"
grep -q "^stdio-ok$" "$TMP_DIR/stdout.log"

echo "M14_STAGE3_SYS_STDIO_INTRINSICS:PASS"
