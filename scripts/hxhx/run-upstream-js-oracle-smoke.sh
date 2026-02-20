#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"
HXHX_BIN="${HXHX_BIN:-}"
REQUIRE_HAXE_437_RAW="${HXHX_JS_ORACLE_REQUIRE_HAXE_437:-1}"
FIXTURE_FILTER="${HXHX_JS_ORACLE_FIXTURES:-}"
FORBID_STAGE0="${HXHX_FORBID_STAGE0:-1}"

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

REQUIRE_HAXE_437="$(parse_bool HXHX_JS_ORACLE_REQUIRE_HAXE_437 "$REQUIRE_HAXE_437_RAW")"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "Missing node on PATH (required for JS oracle runtime checks)." >&2
  exit 1
fi

if [ -z "$HXHX_BIN" ]; then
  HXHX_BIN="$($ROOT/scripts/hxhx/build-hxhx.sh | tail -n 1)"
fi
if [ ! -f "$HXHX_BIN" ]; then
  echo "Failed to locate built hxhx binary." >&2
  exit 1
fi

haxe_version="$("$HAXE_BIN" --version | head -n 1 | tr -d '\r')"
if [ "$REQUIRE_HAXE_437" = "1" ] && [[ ! "$haxe_version" =~ ^4\.3\.7 ]]; then
  echo "Expected upstream oracle compiler version 4.3.7, got: ${haxe_version}" >&2
  echo "Override with HXHX_JS_ORACLE_REQUIRE_HAXE_437=0 if this is intentional." >&2
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

if ! ensure_target_available "js-native"; then
  echo "hxhx binary does not expose --target js-native (required for this oracle smoke)." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$tmpdir/src" "$tmpdir/logs" "$tmpdir/out/upstream" "$tmpdir/out/hxhx"

cat >"$tmpdir/src/JsOracleLoopMain.hx" <<'HX'
class JsOracleLoopMain {
  static function main() {
    var sum = 0;
    for (i in 0...3) {
      sum += i;
    }
    if (sum > 0) {
      sum += sum;
    }
    trace("JS_ORACLE|loop:" + sum);
  }
}
HX

cat >"$tmpdir/src/JsOracleSwitchExprMain.hx" <<'HX'
class JsOracleSwitchExprMain {
  static function main() {
    var mode = "b";
    var picked = switch (mode) {
      case "a":
        1;
      case "b" | "c":
        2;
      default:
        9;
    };

    var bound = switch (mode) {
      case value:
        value + "-ok";
    };

    trace("JS_ORACLE|switch-expr:" + picked + ":" + bound);
  }
}
HX

cat >"$tmpdir/src/JsOracleEnumReflectionMain.hx" <<'HX'
enum JsOracleMode {
  Build;
  Run;
}

class JsOracleEnumReflectionMain {
  static function main() {
    var mode = Run;
    var label = "none";
    switch (mode) {
      case Build:
        label = "build";
      case Run:
        label = "run";
      default:
        label = "other";
    }

    var cls = Type.resolveClass("JsOracleEnumReflectionMain");
    trace("JS_ORACLE|enum-switch:" + label);
    trace("JS_ORACLE|class-name:" + Type.getClassName(cls));
    trace("JS_ORACLE|enum-ctor:" + Type.enumConstructor(mode));
    trace("JS_ORACLE|enum-params:" + Type.enumParameters(mode).length);
  }
}
HX

cat >"$tmpdir/src/JsOracleTryCatchMain.hx" <<'HX'
class JsOracleTryCatchMain {
  static function main() {
    var msg = "start";
    try {
      throw "boom";
    } catch (err:Dynamic) {
      msg = "caught:" + err;
      try {
        throw err;
      } catch (inner:Dynamic) {
        msg = msg + "|rethrow:" + inner;
      }
    }
    trace("JS_ORACLE|try-catch:" + msg);
  }
}
HX

cat >"$tmpdir/src/JsOracleArrayComprehensionMain.hx" <<'HX'
class JsOracleArrayComprehensionMain {
  static function main() {
    var doubled = [for (i in 0...4) i * 2];
    var shifted = [for (value in doubled) value + 1];
    trace("JS_ORACLE|arr-comp:" + shifted.length + ":" + shifted[0] + ":" + shifted[3]);
  }
}
HX

all_fixtures=(
  "JsOracleLoopMain"
  "JsOracleSwitchExprMain"
  "JsOracleEnumReflectionMain"
  "JsOracleTryCatchMain"
  "JsOracleArrayComprehensionMain"
)

selected_fixtures=()
if [ -n "$FIXTURE_FILTER" ]; then
  IFS=',' read -r -a requested <<<"$FIXTURE_FILTER"
  for item in "${requested[@]}"; do
    name="$(printf '%s' "$item" | xargs)"
    if [ -z "$name" ]; then
      continue
    fi
    found=0
    for candidate in "${all_fixtures[@]}"; do
      if [ "$candidate" = "$name" ]; then
        selected_fixtures+=("$name")
        found=1
        break
      fi
    done
    if [ "$found" -ne 1 ]; then
      echo "Unknown fixture in HXHX_JS_ORACLE_FIXTURES: $name" >&2
      exit 2
    fi
  done
else
  selected_fixtures=("${all_fixtures[@]}")
fi

if [ "${#selected_fixtures[@]}" -eq 0 ]; then
  echo "No fixtures selected for JS oracle smoke." >&2
  exit 2
fi

extract_oracle_lines() {
  local input="$1"
  local output="$2"
  sed -n -E 's/^.*(JS_ORACLE\|.*)$/\1/p' "$input" >"$output"
}

run_fixture() {
  local main="$1"
  local up_js="$tmpdir/out/upstream/${main}.js"
  local hx_js="$tmpdir/out/hxhx/${main}.js"
  local up_compile_log="$tmpdir/logs/${main}.upstream.compile.log"
  local hx_compile_log="$tmpdir/logs/${main}.hxhx.compile.log"
  local up_run_log="$tmpdir/logs/${main}.upstream.run.log"
  local hx_run_log="$tmpdir/logs/${main}.hxhx.run.log"
  local up_norm="$tmpdir/logs/${main}.upstream.oracle.txt"
  local hx_norm="$tmpdir/logs/${main}.hxhx.oracle.txt"
  local diff_log="$tmpdir/logs/${main}.oracle.diff"

  if ! "$HAXE_BIN" -cp "$tmpdir/src" -main "$main" -js "$up_js" >"$up_compile_log" 2>&1; then
    echo "js_oracle_smoke=fail" >&2
    echo "fixture=${main}" >&2
    echo "reason=upstream_compile_failed" >&2
    cat "$up_compile_log" >&2
    exit 1
  fi

  if ! HAXE_BIN=/definitely-not-used HXHX_FORBID_STAGE0="$FORBID_STAGE0" \
    "$HXHX_BIN" --target js-native --hxhx-no-run --js "$hx_js" -cp "$tmpdir/src" -main "$main" \
    --hxhx-out "$tmpdir/out/hxhx/${main}" >"$hx_compile_log" 2>&1; then
    echo "js_oracle_smoke=fail" >&2
    echo "fixture=${main}" >&2
    echo "reason=hxhx_compile_failed" >&2
    cat "$hx_compile_log" >&2
    exit 1
  fi

  set +e
  node "$up_js" >"$up_run_log" 2>&1
  up_status=$?
  node "$hx_js" >"$hx_run_log" 2>&1
  hx_status=$?
  set -e

  extract_oracle_lines "$up_run_log" "$up_norm"
  extract_oracle_lines "$hx_run_log" "$hx_norm"

  if [ ! -s "$up_norm" ] || [ ! -s "$hx_norm" ]; then
    echo "js_oracle_smoke=fail" >&2
    echo "fixture=${main}" >&2
    echo "reason=missing_oracle_output" >&2
    echo "-- upstream runtime --" >&2
    cat "$up_run_log" >&2
    echo "-- hxhx runtime --" >&2
    cat "$hx_run_log" >&2
    exit 1
  fi

  if [ "$up_status" -ne "$hx_status" ]; then
    echo "js_oracle_smoke=fail" >&2
    echo "fixture=${main}" >&2
    echo "reason=exit_code_mismatch upstream=${up_status} hxhx=${hx_status}" >&2
    echo "-- upstream runtime --" >&2
    cat "$up_run_log" >&2
    echo "-- hxhx runtime --" >&2
    cat "$hx_run_log" >&2
    exit 1
  fi

  if ! diff -u "$up_norm" "$hx_norm" >"$diff_log"; then
    echo "js_oracle_smoke=fail" >&2
    echo "fixture=${main}" >&2
    echo "reason=oracle_output_mismatch" >&2
    cat "$diff_log" >&2
    echo "-- upstream runtime --" >&2
    cat "$up_run_log" >&2
    echo "-- hxhx runtime --" >&2
    cat "$hx_run_log" >&2
    exit 1
  fi

  echo "fixture=${main} status=ok lines=$(wc -l <"$up_norm" | tr -d ' ')"
}

echo "== upstream js oracle smoke"
echo "haxe_bin=$HAXE_BIN"
echo "haxe_version=$haxe_version"
echo "hxhx_bin=$HXHX_BIN"
echo "fixtures=${selected_fixtures[*]}"

for fixture in "${selected_fixtures[@]}"; do
  run_fixture "$fixture"
done

echo "js_oracle_smoke=ok fixtures=${#selected_fixtures[@]}"
