#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"
REPS_RAW="${HXHX_BUILTIN_SMOKE_REPS:-1}"
OCAML_LANE_RAW="${HXHX_BUILTIN_SMOKE_OCAML:-1}"
JS_NATIVE_LANE_RAW="${HXHX_BUILTIN_SMOKE_JS_NATIVE:-0}"
REQUIRE_JS_NATIVE_RAW="${HXHX_BUILTIN_SMOKE_REQUIRE_JS_NATIVE:-0}"

parse_bool() {
  local name="$1"
  local raw="$2"
  local norm
  norm="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$norm" in
    1|true|yes|on) echo "1" ;;
    0|false|no|off|'') echo "0" ;;
    *)
      echo "Invalid ${name}: ${raw} (expected one of: 0/1, true/false, yes/no, on/off)." >&2
      exit 2
      ;;
  esac
}

OCAML_LANE="$(parse_bool HXHX_BUILTIN_SMOKE_OCAML "$OCAML_LANE_RAW")"
JS_NATIVE_LANE="$(parse_bool HXHX_BUILTIN_SMOKE_JS_NATIVE "$JS_NATIVE_LANE_RAW")"
REQUIRE_JS_NATIVE="$(parse_bool HXHX_BUILTIN_SMOKE_REQUIRE_JS_NATIVE "$REQUIRE_JS_NATIVE_RAW")"

if [ "$OCAML_LANE" != "1" ] && [ "$JS_NATIVE_LANE" != "1" ]; then
  echo "Nothing to run: both HXHX_BUILTIN_SMOKE_OCAML and HXHX_BUILTIN_SMOKE_JS_NATIVE are disabled." >&2
  exit 2
fi

if [ "$OCAML_LANE" = "1" ]; then
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
else
  REPS=0
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi
if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Missing dune/ocamlc on PATH (required to build hxhx)." >&2
  exit 1
fi
if [ "$OCAML_LANE" = "1" ] && ! command -v python3 >/dev/null 2>&1; then
  echo "Missing python3 on PATH (required for timing)." >&2
  exit 1
fi
if [ "$JS_NATIVE_LANE" = "1" ] && ! command -v node >/dev/null 2>&1; then
  echo "Missing node on PATH (required to run js-native smoke)." >&2
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

ensure_target_available() {
  local target="$1"
  local targets=""
  if ! targets="$("$HXHX_BIN" --hxhx-list-targets 2>/dev/null)"; then
    return 1
  fi
  printf '%s\n' "$targets" | grep -qx "$target"
}

JS_NATIVE_AVAILABLE=1
if [ "$JS_NATIVE_LANE" = "1" ] && ! ensure_target_available "js-native"; then
  JS_NATIVE_AVAILABLE=0
  if [ "$REQUIRE_JS_NATIVE" = "1" ]; then
    echo "hxhx binary does not expose --target js-native and HXHX_BUILTIN_SMOKE_REQUIRE_JS_NATIVE=1." >&2
    exit 1
  fi
  echo "WARN: current hxhx binary does not expose --target js-native; skipping js-native smoke lane." >&2
  echo "      Set HXHX_BUILTIN_SMOKE_REQUIRE_JS_NATIVE=1 to fail when js-native is unavailable." >&2
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

cat > "$tmpdir/src/JsNativeMain.hx" <<'HX'
class JsNativeMain {
  static function main() {
    var sum = 0;
    for (i in 0...4) {
      sum += i;
    }
    Sys.println("js-native-smoke:" + sum);
  }
}
HX

delegate_total=0
builtin_total=0

echo "== builtin target smoke (delegated vs builtin)"
echo "hxhx_bin=$HXHX_BIN"
echo "ocaml_lane=$OCAML_LANE"
echo "js_native_lane=$JS_NATIVE_LANE"

if [ "$OCAML_LANE" = "1" ]; then
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
else
  echo "delegate_avg_ms=skipped"
  echo "builtin_avg_ms=skipped"
  echo "delegate_over_builtin_speedup=skipped"
fi

if [ "$JS_NATIVE_LANE" = "1" ]; then
  if [ "$JS_NATIVE_AVAILABLE" != "1" ]; then
    echo "js_native_smoke=skipped"
    echo "builtin_target_smoke=ok"
    exit 0
  fi
  echo "== js-native emit+run smoke"
  js_artifact="$tmpdir/out_js_native/main.js"
  if ! js_out="$("$HXHX_BIN" --target js-native --js "$js_artifact" -cp "$tmpdir/src" -main JsNativeMain --hxhx-out "$tmpdir/out_js_native" 2>&1)"; then
    echo "builtin_target_smoke=fail" >&2
    echo "mode=js-native" >&2
    printf '%s\n' "$js_out" >&2
    exit 1
  fi
  printf '%s\n' "$js_out"
  if ! printf '%s\n' "$js_out" | grep -q '^stage3=ok$'; then
    echo "builtin_target_smoke=fail" >&2
    echo "mode=js-native" >&2
    echo "Expected stage3=ok marker in js-native output." >&2
    exit 1
  fi
  if ! printf '%s\n' "$js_out" | grep -q "^artifact=${js_artifact}$"; then
    echo "builtin_target_smoke=fail" >&2
    echo "mode=js-native" >&2
    echo "Expected artifact marker for js-native output path." >&2
    exit 1
  fi
  if ! printf '%s\n' "$js_out" | grep -q '^run=ok$'; then
    echo "builtin_target_smoke=fail" >&2
    echo "mode=js-native" >&2
    echo "Expected run=ok marker in js-native output." >&2
    exit 1
  fi
  if ! printf '%s\n' "$js_out" | grep -q '^js-native-smoke:6$'; then
    echo "builtin_target_smoke=fail" >&2
    echo "mode=js-native" >&2
    echo "Expected js-native runtime output marker." >&2
    exit 1
  fi
  if [ ! -f "$js_artifact" ]; then
    echo "builtin_target_smoke=fail" >&2
    echo "mode=js-native" >&2
    echo "Expected emitted JS artifact at: $js_artifact" >&2
    exit 1
  fi
  echo "js_native_artifact=${js_artifact}"
  echo "js_native_smoke=ok"
else
  echo "js_native_smoke=skipped"
fi

echo "builtin_target_smoke=ok"
