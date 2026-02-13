#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"
REPS_RAW="${HXHX_BUILTIN_SMOKE_REPS:-1}"

case "$REPS_RAW" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_BUILTIN_SMOKE_REPS: $REPS_RAW (expected positive integer)." >&2
    exit 2
    ;;
esac
if [ "$REPS_RAW" -le 0 ]; then
  echo "Invalid HXHX_BUILTIN_SMOKE_REPS: $REPS_RAW (expected positive integer)." >&2
  exit 2
fi
REPS="$REPS_RAW"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi
if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Missing dune/ocamlc on PATH (required to build hxhx)." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Missing python3 on PATH (required for timing)." >&2
  exit 1
fi

HXHX_BIN="${HXHX_BIN:-}"
if [ -z "$HXHX_BIN" ]; then
  HXHX_BIN="$($ROOT/scripts/hxhx/build-hxhx.sh | tail -n 1)"
fi
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Failed to locate built hxhx binary." >&2
  exit 1
fi

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

run_timed() {
  local mode="$1"
  shift
  local out=""
  local start end elapsed
  start="$(now_ms)"
  if ! out="$($@ 2>&1)"; then
    echo "builtin_target_smoke=fail" >&2
    echo "mode=${mode}" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
  end="$(now_ms)"
  elapsed=$((end - start))

  if [ "$mode" = "builtin" ]; then
    if ! printf '%s\n' "$out" | grep -q '^stage3=no_emit_ok$'; then
      echo "builtin_target_smoke=fail" >&2
      echo "mode=builtin" >&2
      echo "Expected stage3=no_emit_ok marker in builtin mode output." >&2
      printf '%s\n' "$out" >&2
      exit 1
    fi
  fi

  printf '%s\n' "$elapsed"
}

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$tmpdir/src"
cat > "$tmpdir/src/Main.hx" <<'HX'
class Main {
  static function main() {
    Sys.println("builtin-smoke");
  }
}
HX

delegate_total=0
builtin_total=0

echo "== builtin target smoke (delegated vs builtin)"
echo "hxhx_bin=$HXHX_BIN"
echo "reps=$REPS"

for i in $(seq 1 "$REPS"); do
  delegate_ms="$(run_timed delegated "$HXHX_BIN" --target ocaml -- -cp "$tmpdir/src" -main Main --no-output -D ocaml_no_build -D "ocaml_output=$tmpdir/out_delegate")"
  builtin_ms="$(run_timed builtin "$HXHX_BIN" --target ocaml-stage3 --hxhx-no-emit -cp "$tmpdir/src" -main Main --hxhx-out "$tmpdir/out_builtin")"

  delegate_total=$((delegate_total + delegate_ms))
  builtin_total=$((builtin_total + builtin_ms))

  echo "rep=${i} delegated_ms=${delegate_ms} builtin_ms=${builtin_ms}"
done

delegate_avg=$((delegate_total / REPS))
builtin_avg=$((builtin_total / REPS))

speedup="n/a"
if [ "$builtin_avg" -gt 0 ]; then
  speedup="$(python3 - <<PY
print(f"{${delegate_avg}/${builtin_avg}:.2f}x")
PY
)"
fi

echo "delegate_avg_ms=${delegate_avg}"
echo "builtin_avg_ms=${builtin_avg}"
echo "delegate_over_builtin_speedup=${speedup}"
echo "builtin_target_smoke=ok"
