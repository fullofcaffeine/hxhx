#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FETCH_SCRIPT="$ROOT/scripts/vendor/fetch-reflaxe-elixir-upstream.sh"
PILOT_SCRIPT="$ROOT/scripts/hxhx/run-reflaxe-elixir-todo-promotion-pilot.sh"
SUMMARY_SCRIPT="$ROOT/scripts/ci/reflaxe-elixir-native-verification-summary.js"

RUN_ID="${PYBM_RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"
ARTIFACT_DIR="${PYBM_ARTIFACT_DIR:-$ROOT/.artifacts/pybm/reflaxe-elixir-native-verify/$RUN_ID}"
LANES="${PYBM_LANES:-official-native-path,runtime-smoke,todo-build-tests}"
if [ "$LANES" = "all" ]; then
  LANES="official-native-path,runtime-smoke,todo-build-tests"
fi

mkdir -p "$ARTIFACT_DIR"

has_lane() {
  local wanted="$1"
  case ",$LANES," in
    *",${wanted},"*) return 0 ;;
    *) return 1 ;;
  esac
}

require_executable() {
  if [ ! -x "$1" ]; then
    echo "reflaxe-elixir native verification: missing executable: $1" >&2
    exit 2
  fi
}

resolve_source_repo() {
  if [ -n "${REFLAXE_ELIXIR_DIR:-}" ]; then
    if [ ! -d "$REFLAXE_ELIXIR_DIR/.git" ]; then
      echo "reflaxe-elixir native verification: REFLAXE_ELIXIR_DIR is not a git repo: $REFLAXE_ELIXIR_DIR" >&2
      exit 2
    fi
    printf '%s\n' "$REFLAXE_ELIXIR_DIR"
    return
  fi
  if [ -d "$ROOT/vendor/reflaxe-elixir/.git" ]; then
    printf '%s\n' "$ROOT/vendor/reflaxe-elixir"
    return
  fi
  if [ ! -x "$FETCH_SCRIPT" ]; then
    echo "reflaxe-elixir native verification: missing fetch script: $FETCH_SCRIPT" >&2
    exit 2
  fi
  local fetch_output
  fetch_output="$(bash "$FETCH_SCRIPT")"
  printf '%s\n' "$fetch_output" >&2
  printf '%s\n' "$fetch_output" | awk -F= '/^reflaxe_elixir_dir=/{print $2}' | tail -n1
}

resolve_hxhx_bin() {
  if [ -n "${HXHX_BIN:-}" ]; then
    if [ ! -x "$HXHX_BIN" ]; then
      echo "reflaxe-elixir native verification: HXHX_BIN is not executable: $HXHX_BIN" >&2
      exit 2
    fi
    printf '%s\n' "$HXHX_BIN"
    return
  fi
  bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1
}

classify_failure() {
  local lane_dir="$1"
  if grep -q 'Native source-host Reflaxe target' "$lane_dir/native.stderr.log" "$lane_dir/native.stdout.log"; then
    printf '%s\n' "native_source_target_unimplemented"
  elif grep -q 'No target selected' "$lane_dir/native.stderr.log" "$lane_dir/native.stdout.log"; then
    printf '%s\n' "no_target_selected"
  elif grep -q 'Target not supported natively' "$lane_dir/native.stderr.log" "$lane_dir/native.stdout.log"; then
    printf '%s\n' "native_target_unimplemented"
  elif grep -q 'stage0 delegation is forbidden' "$lane_dir/native.stderr.log" "$lane_dir/native.stdout.log"; then
    printf '%s\n' "stage0_forbidden"
  else
    printf '%s\n' "command_failed"
  fi
}

run_official_native_path() {
  local lane_dir="$ARTIFACT_DIR/official-native-path"
  mkdir -p "$lane_dir"
  set +e
  HXHX_PILOT_ARTIFACT_DIR="$lane_dir" bash "$PILOT_SCRIPT" >"$lane_dir/stdout.log" 2>"$lane_dir/stderr.log"
  local code="$?"
  set -e
  cat "$lane_dir/stdout.log"
  if [ "$code" -ne 0 ]; then
    cat "$lane_dir/stderr.log" >&2
  fi
  {
    if [ "$code" -eq 0 ]; then
      echo "status=pass"
    else
      echo "status=fail"
    fi
    echo "exit_code=$code"
  } >"$ARTIFACT_DIR/official-native-path.result.env"
  return "$code"
}

run_source_host_lane() {
  local lane="$1"
  local hxhx_bin="$2"
  local cwd="$3"
  shift 3
  local lane_dir="$ARTIFACT_DIR/diagnostic-source-host/$lane"
  mkdir -p "$lane_dir"

  set +e
  (
    cd "$cwd"
    HXHX_FORBID_STAGE0=1 "$hxhx_bin" "$@"
  ) >"$lane_dir/native.stdout.log" 2>"$lane_dir/native.stderr.log"
  local code="$?"
  set -e

  local status="fail"
  local category=""
  if [ "$code" -eq 0 ]; then
    status="pass"
  else
    category="$(classify_failure "$lane_dir")"
  fi

  {
    echo "status=$status"
    echo "exit_code=$code"
    echo "failure_category=$category"
    echo "cwd=$cwd"
    printf 'command=%s' "$hxhx_bin"
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
  } >"$lane_dir/result.env"

  if [ "$status" = "fail" ]; then
    echo "diagnostic_source_host_${lane}_failure_category=$category"
  fi
}

require_executable "$PILOT_SCRIPT"
require_executable "$SUMMARY_SCRIPT"

source_repo="$(resolve_source_repo)"
source_commit="$(git -C "$source_repo" rev-parse HEAD)"
echo "reflaxe_elixir_native_verify_source_repo=$source_repo"
echo "reflaxe_elixir_native_verify_source_commit=$source_commit"
echo "reflaxe_elixir_native_verify_artifact_dir=$ARTIFACT_DIR"
echo "reflaxe_elixir_native_verify_lanes=$LANES"

official_status=0
if has_lane "official-native-path"; then
  run_official_native_path || official_status="$?"
fi

diagnostic_hxhx_bin=""
if has_lane "runtime-smoke" || has_lane "todo-build-tests"; then
  diagnostic_hxhx_bin="$(resolve_hxhx_bin)"
  if [ ! -x "$diagnostic_hxhx_bin" ]; then
    echo "reflaxe-elixir native verification: failed to build hxhx binary: $diagnostic_hxhx_bin" >&2
    exit 2
  fi
fi

if has_lane "runtime-smoke"; then
  run_source_host_lane \
    "runtime-smoke" \
    "$diagnostic_hxhx_bin" \
    "$source_repo/test/snapshot/core/try_catch" \
    "compile.hxml"
fi

if has_lane "todo-build-tests"; then
  run_source_host_lane \
    "todo-build-tests" \
    "$diagnostic_hxhx_bin" \
    "$source_repo/examples/todo-app" \
    "build-tests.hxml"
fi

summary_path="$ARTIFACT_DIR/reflaxe-elixir-native-verify.summary.json"
node "$SUMMARY_SCRIPT" \
  --artifact-dir "$ARTIFACT_DIR" \
  --json-out "$summary_path" \
  --lanes "$LANES" \
  --source-repo "$source_repo" \
  --source-commit "$source_commit"

if [ "$official_status" -ne 0 ]; then
  exit "$official_status"
fi
