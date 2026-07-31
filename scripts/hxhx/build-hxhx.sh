#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXE_CONNECT="${HAXE_CONNECT:-}"
HXHX_STAGE0_USE_REPO_SERVER="${HXHX_STAGE0_USE_REPO_SERVER:-0}"
HXHX_STAGE0_KEEP_REPO_SERVER="${HXHX_STAGE0_KEEP_REPO_SERVER:-0}"
HXHX_FORCE_STAGE0="${HXHX_FORCE_STAGE0:-0}"
HXHX_FORBID_STAGE0="${HXHX_FORBID_STAGE0:-0}"
HXHX_STAGE0_PROGRESS="${HXHX_STAGE0_PROGRESS:-0}"
HXHX_STAGE0_TELEMETRY="${HXHX_STAGE0_TELEMETRY:-0}"
HXHX_STAGE0_TELEMETRY_DETAIL="${HXHX_STAGE0_TELEMETRY_DETAIL:-0}"
HXHX_STAGE0_TELEMETRY_CLASS="${HXHX_STAGE0_TELEMETRY_CLASS:-}"
HXHX_STAGE0_TELEMETRY_FIELD="${HXHX_STAGE0_TELEMETRY_FIELD:-}"
HXHX_STAGE0_OCAML_BUILD="${HXHX_STAGE0_OCAML_BUILD:-byte}"
HXHX_STAGE0_PREFER_NATIVE="${HXHX_STAGE0_PREFER_NATIVE:-0}"
HXHX_STAGE0_TIMES="${HXHX_STAGE0_TIMES:-0}"
HXHX_STAGE0_VERBOSE="${HXHX_STAGE0_VERBOSE:-0}"
HXHX_STAGE0_DISABLE_PREPASSES="${HXHX_STAGE0_DISABLE_PREPASSES:-0}"
HXHX_STAGE0_NO_INLINE="${HXHX_STAGE0_NO_INLINE:-0}"
HXHX_STAGE0_NO_OPT="${HXHX_STAGE0_NO_OPT:-0}"
HXHX_STAGE0_NO_EXPR_MACROS="${HXHX_STAGE0_NO_EXPR_MACROS:-0}"
HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST="${HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST:-0}"
HXHX_STAGE0_NO_INTERNAL_TOOLS="${HXHX_STAGE0_NO_INTERNAL_TOOLS:-0}"
HXHX_STAGE0_NO_DISPLAY="${HXHX_STAGE0_NO_DISPLAY:-0}"
HXHX_STAGE0_OCAML_ONLY="${HXHX_STAGE0_OCAML_ONLY:-0}"
HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY="${HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY:-0}"
HXHX_STAGE0_HEARTBEAT="${HXHX_STAGE0_HEARTBEAT:-30}"
HXHX_STAGE0_LOG_TAIL_LINES="${HXHX_STAGE0_LOG_TAIL_LINES:-80}"
HXHX_STAGE0_FAILFAST_SECS="${HXHX_STAGE0_FAILFAST_SECS:-7200}"
HXHX_STAGE0_HEARTBEAT_TAIL_LINES="${HXHX_STAGE0_HEARTBEAT_TAIL_LINES:-0}"
HXHX_STAGE0_MAX_RSS_MB="${HXHX_STAGE0_MAX_RSS_MB:-0}"
HXHX_STAGE0_CONNECT_IDLE_SECS="${HXHX_STAGE0_CONNECT_IDLE_SECS:-180}"
HXHX_KEEP_LOGS="${HXHX_KEEP_LOGS:-0}"
HXHX_LOG_DIR="${HXHX_LOG_DIR:-}"
HXHX_BOOTSTRAP_HEARTBEAT="${HXHX_BOOTSTRAP_HEARTBEAT:-20}"
HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS="${HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS:-0}"
HXHX_DUNE_JOBS="${HXHX_DUNE_JOBS:-auto}"
HXHX_BOOTSTRAP_BUILD_PRUNE="${HXHX_BOOTSTRAP_BUILD_PRUNE:-1}"
HXHX_BOOTSTRAP_BUILD_RETAIN="${HXHX_BOOTSTRAP_BUILD_RETAIN:-2}"
HXHX_BOOTSTRAP_BUILD_PRUNE_ONLY="${HXHX_BOOTSTRAP_BUILD_PRUNE_ONLY:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HXHX_DIR="$ROOT/packages/hxhx"
BOOTSTRAP_DIR="$HXHX_DIR/bootstrap_out"
DEFAULT_STAGE0_OUT_DIR="$HXHX_DIR/out"
STAGE0_OUT_DIR_RAW="${HXHX_STAGE0_OUTPUT_DIR:-$DEFAULT_STAGE0_OUT_DIR}"
case "$STAGE0_OUT_DIR_RAW" in
  /*) STAGE0_OUT_DIR="$STAGE0_OUT_DIR_RAW" ;;
  *) STAGE0_OUT_DIR="$ROOT/$STAGE0_OUT_DIR_RAW" ;;
esac
mkdir -p "$STAGE0_OUT_DIR"
STAGE0_OUT_DIR="$(cd "$STAGE0_OUT_DIR" && pwd -P)"

# Stage0 generation replaces its complete output directory. Refuse locations
# that contain tracked repository inputs so an incorrect development override
# cannot delete source, configuration, or committed bootstrap snapshots.
case "$STAGE0_OUT_DIR" in
  /|"$ROOT"|"$HXHX_DIR"|"$BOOTSTRAP_DIR")
    echo "Unsafe HXHX_STAGE0_OUTPUT_DIR: $STAGE0_OUT_DIR" >&2
    exit 2
    ;;
esac
if [[ "$STAGE0_OUT_DIR" == "$ROOT/"* ]]; then
  stage0_out_repo_relative="${STAGE0_OUT_DIR#"$ROOT/"}"
  if git -C "$ROOT" ls-files -- "$stage0_out_repo_relative" | grep -q .; then
    echo "Unsafe HXHX_STAGE0_OUTPUT_DIR contains tracked files: $STAGE0_OUT_DIR" >&2
    exit 2
  fi
fi

stage0_executable_name() {
  local dune_file="$STAGE0_OUT_DIR/dune"
  local name=""
  if [ -f "$dune_file" ]; then
    name="$(sed -nE 's/^[[:space:]]*\(name[[:space:]]+([A-Za-z0-9_]+)\).*/\1/p' "$dune_file" | head -n 1)"
  fi
  if [ -z "$name" ]; then
    name="$(basename "$STAGE0_OUT_DIR" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]/_/g')"
    case "$name" in
      [0-9]*) name="_$name" ;;
    esac
  fi
  case "$name" in
    ''|*[!A-Za-z0-9_]*)
      echo "Cannot resolve a safe generated executable name from $dune_file" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$name"
}
BOOTSTRAP_BUILD_DIR="${HXHX_BOOTSTRAP_BUILD_DIR:-}"
BOOTSTRAP_BUILD_DIR_AUTOCREATED=0
HAXE_SERVER_HELPER="$ROOT/scripts/hxhx/haxe-server.sh"
BOOTSTRAP_BUILD_PID_FILE=".hxhx-bootstrap-build.pid"
is_true() {
  local v="${1:-}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

bootstrap_build_dir_is_active() {
  local dir="${1:-}"
  local pid_file=""
  local owner_pid=""

  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    return 1
  fi
  pid_file="$dir/$BOOTSTRAP_BUILD_PID_FILE"
  if [ ! -f "$pid_file" ]; then
    return 1
  fi
  owner_pid="$(head -n 1 "$pid_file" 2>/dev/null | tr -d '[:space:]' || true)"
  case "$owner_pid" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  kill -0 "$owner_pid" >/dev/null 2>&1
}

prune_stale_bootstrap_build_dirs() {
  local current_dir="${1:-}"
  local retain="$HXHX_BOOTSTRAP_BUILD_RETAIN"
  local kept_inactive=0
  local pruned=0
  local dir=""
  local -a candidates=()
  local -a sorted_candidates=()

  if [ "$HXHX_BOOTSTRAP_BUILD_PRUNE" != "1" ]; then
    return 0
  fi
  if [ ! -d "$ROOT/.tmp" ]; then
    return 0
  fi
  case "$retain" in
    ''|*[!0-9]*)
      retain=2
      ;;
  esac

  shopt -s nullglob
  candidates=("$ROOT/.tmp"/hxhx-bootstrap-build.*)
  shopt -u nullglob
  if [ "${#candidates[@]}" -eq 0 ]; then
    return 0
  fi
  while IFS= read -r dir; do
    sorted_candidates+=("$dir")
  done < <(ls -dt "${candidates[@]}" 2>/dev/null || true)

  for dir in "${sorted_candidates[@]}"; do
    if [ ! -d "$dir" ]; then
      continue
    fi
    if [ -n "$current_dir" ] && [ "$dir" = "$current_dir" ]; then
      continue
    fi
    if bootstrap_build_dir_is_active "$dir"; then
      continue
    fi
    kept_inactive="$((kept_inactive + 1))"
    if [ "$kept_inactive" -le "$retain" ]; then
      continue
    fi
    rm -rf "$dir"
    pruned="$((pruned + 1))"
    echo "== Pruned stale bootstrap build dir: $dir" >&2
  done
  if [ "$pruned" -gt 0 ]; then
    echo "== Pruned $pruned stale bootstrap build dir(s); retained newest inactive=$retain" >&2
  fi
}

resolve_bootstrap_build_dir() {
  if [ -n "$BOOTSTRAP_BUILD_DIR" ]; then
    if [[ "$BOOTSTRAP_BUILD_DIR" != /* ]]; then
      echo "$ROOT/$BOOTSTRAP_BUILD_DIR"
    else
      echo "$BOOTSTRAP_BUILD_DIR"
    fi
    return 0
  fi

  # Default bootstrap builds should not contend on a single shared `bootstrap_work`
  # workspace. Interrupted or concurrent dune builds can otherwise leave stale locks
  # or mutate the same copied snapshot under later callers.
  BOOTSTRAP_BUILD_DIR_AUTOCREATED=1
  mkdir -p "$ROOT/.tmp"
  prune_stale_bootstrap_build_dirs ""
  local dir
  dir="$(mktemp -d "$ROOT/.tmp/hxhx-bootstrap-build.XXXXXX")"
  printf '%s\n' "$$" >"$dir/$BOOTSTRAP_BUILD_PID_FILE" 2>/dev/null || true
  echo "$dir"
}

if [ "$HXHX_BOOTSTRAP_BUILD_PRUNE_ONLY" = "1" ]; then
  prune_stale_bootstrap_build_dirs ""
  exit 0
fi

BOOTSTRAP_BUILD_DIR="$(resolve_bootstrap_build_dir)"

preserve_bootstrap_failure_artifacts() {
  local build_dir="${1:-}"
  local failed_target="${2:-}"
  local failed_code="${3:-1}"
  local artifact_dir=""
  local copied=0
  local path=""

  if [ -z "$build_dir" ] || [ ! -d "$build_dir" ]; then
    return 0
  fi

  mkdir -p "$ROOT/.tmp"
  artifact_dir="$(mktemp -d "$ROOT/.tmp/hxhx-bootstrap-failure.XXXXXX")"

  for path in \
    "$build_dir/EmitterStage.ml" \
    "$build_dir/EmitterStage.ml.parts" \
    "$build_dir"/EmitterStage.ml.part* \
    "$build_dir/backend_js_JsTargetCore.ml" \
    "$build_dir/hxhx_CliRouting.ml" \
    "$build_dir/dune" \
    "$build_dir/_build/log"
  do
    if [ ! -e "$path" ]; then
      continue
    fi
    cp -R "$path" "$artifact_dir/" 2>/dev/null || true
    copied=1
  done

  cat >"$artifact_dir/summary.txt" <<EOF
bootstrap_build_dir=$build_dir
failed_target=$failed_target
exit_code=$failed_code
EOF

  if [ "$copied" = "1" ]; then
    echo "== bootstrap failure artifacts: $artifact_dir" >&2
  else
    echo "== bootstrap failure artifacts: $artifact_dir (summary-only)" >&2
  fi
}

create_stage0_log_file() {
  local prefix="$1"
  local template=""
  if [ -n "$HXHX_LOG_DIR" ]; then
    mkdir -p "$HXHX_LOG_DIR"
    template="${HXHX_LOG_DIR%/}/${prefix}.XXXXXX"
  else
    template="${TMPDIR:-/tmp}/${prefix}.XXXXXX"
  fi
  mktemp "$template"
}

cleanup_stage0_log_file() {
  local path="$1"
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    return
  fi
  if [ "$HXHX_KEEP_LOGS" = "1" ]; then
    echo "== Stage0 build log retained: $path" >&2
  else
    rm -f "$path"
  fi
}
collect_process_tree_pids() {
  local root_pid="$1"
  local frontier="$root_pid"
  local seen=" $root_pid "
  local collected="$root_pid"
  local parent_pid=""
  local child_pids=""
  local child_pid=""
  local next_frontier=""

  while [ -n "$frontier" ]; do
    next_frontier=""
    for parent_pid in $frontier; do
      child_pids="$(pgrep -P "$parent_pid" 2>/dev/null || true)"
      if [ -z "$child_pids" ]; then
        continue
      fi
      for child_pid in $child_pids; do
        if [[ "$seen" == *" $child_pid "* ]]; then
          continue
        fi
        seen="$seen$child_pid "
        collected="$collected $child_pid"
        next_frontier="$next_frontier $child_pid"
      done
    done
    frontier="${next_frontier# }"
  done

  echo "$collected"
}

case "$HXHX_BOOTSTRAP_HEARTBEAT" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_BOOTSTRAP_HEARTBEAT: $HXHX_BOOTSTRAP_HEARTBEAT (expected non-negative integer)." >&2
    exit 2
    ;;
esac

case "$HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS: $HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS (expected non-negative integer)." >&2
    exit 2
    ;;
esac

case "$HXHX_DUNE_JOBS" in
  auto) ;;
  ''|*[!0-9]*)
    echo "Invalid HXHX_DUNE_JOBS: $HXHX_DUNE_JOBS (expected 'auto' or a positive integer)." >&2
    exit 2
    ;;
  0)
    echo "Invalid HXHX_DUNE_JOBS: $HXHX_DUNE_JOBS (expected 'auto' or a positive integer)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_HEARTBEAT" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_STAGE0_HEARTBEAT: $HXHX_STAGE0_HEARTBEAT (expected non-negative integer)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_NO_INLINE" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_NO_INLINE: $HXHX_STAGE0_NO_INLINE (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_NO_OPT" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_NO_OPT: $HXHX_STAGE0_NO_OPT (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_NO_EXPR_MACROS" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_NO_EXPR_MACROS: $HXHX_STAGE0_NO_EXPR_MACROS (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST: $HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_NO_INTERNAL_TOOLS" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_NO_INTERNAL_TOOLS: $HXHX_STAGE0_NO_INTERNAL_TOOLS (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_NO_DISPLAY" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_NO_DISPLAY: $HXHX_STAGE0_NO_DISPLAY (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_OCAML_ONLY" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_OCAML_ONLY: $HXHX_STAGE0_OCAML_ONLY (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY: $HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_USE_REPO_SERVER" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_USE_REPO_SERVER: $HXHX_STAGE0_USE_REPO_SERVER (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_KEEP_REPO_SERVER" in
  0|1) ;;
  *)
    echo "Invalid HXHX_STAGE0_KEEP_REPO_SERVER: $HXHX_STAGE0_KEEP_REPO_SERVER (expected 0 or 1)." >&2
    exit 2
    ;;
esac

case "$HXHX_FORBID_STAGE0" in
  0|1|true|false|yes|no|on|off) ;;
  *)
    echo "Invalid HXHX_FORBID_STAGE0: $HXHX_FORBID_STAGE0 (expected boolean-like value)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_FAILFAST_SECS" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_STAGE0_FAILFAST_SECS: $HXHX_STAGE0_FAILFAST_SECS (expected non-negative integer)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_MAX_RSS_MB" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_STAGE0_MAX_RSS_MB: $HXHX_STAGE0_MAX_RSS_MB (expected non-negative integer)." >&2
    exit 2
    ;;
esac

case "$HXHX_STAGE0_CONNECT_IDLE_SECS" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_STAGE0_CONNECT_IDLE_SECS: $HXHX_STAGE0_CONNECT_IDLE_SECS (expected non-negative integer)." >&2
    exit 2
    ;;
esac

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx build: dune/ocamlc not found on PATH." >&2
  exit 0
fi

if [ ! -d "$HXHX_DIR" ]; then
  echo "Missing hxhx package directory: $HXHX_DIR" >&2
  exit 1
fi

if [ "$HXHX_DUNE_JOBS" != "auto" ]; then
  export DUNE_JOBS="$HXHX_DUNE_JOBS"
  echo "== Dune jobs: forced to $HXHX_DUNE_JOBS (HXHX_DUNE_JOBS)" >&2
elif [ -n "${DUNE_JOBS:-}" ]; then
  echo "== Dune jobs: inherited DUNE_JOBS=$DUNE_JOBS (HXHX_DUNE_JOBS=auto)" >&2
else
  echo "== Dune jobs: auto (HXHX_DUNE_JOBS=auto)" >&2
fi

run_bootstrap_dune_build() {
  local target="$1"
  local heartbeat_sec="$HXHX_BOOTSTRAP_HEARTBEAT"
  local timeout_sec="$HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS"

  if [ "$heartbeat_sec" = "0" ] && [ "$timeout_sec" = "0" ]; then
    dune build "$target"
    return
  fi

  dune build "$target" &
  local pid="$!"
  local heartbeat_pid=""
  local timeout_pid=""
  local timeout_marker=""
  local start_hb
  local code=0

  start_hb="$(date +%s)"

  if [ "$timeout_sec" != "0" ]; then
    timeout_marker="$(mktemp -t hxhx-bootstrap-timeout.XXXXXX)"
  fi

  if [ "$heartbeat_sec" != "0" ]; then
    (
      local elapsed=0
      local rss_kb=""
      local rss_mb=0
      while kill -0 "$pid" >/dev/null 2>&1; do
        sleep "$heartbeat_sec" || true
        elapsed="$(( $(date +%s) - start_hb ))"
        if kill -0 "$pid" >/dev/null 2>&1; then
          rss_kb="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
          if [ -n "$rss_kb" ]; then
            rss_mb="$((rss_kb / 1024))"
            echo "== Bootstrap dune heartbeat: target=$target elapsed=${elapsed}s rss=${rss_mb}MB pid=$pid" >&2
          else
            echo "== Bootstrap dune heartbeat: target=$target elapsed=${elapsed}s pid=$pid" >&2
          fi
        fi
      done
    ) &
    heartbeat_pid="$!"
  fi

  if [ "$timeout_sec" != "0" ]; then
    (
      sleep "$timeout_sec"
      if kill -0 "$pid" >/dev/null 2>&1; then
        echo "Bootstrap dune build timed out after ${timeout_sec}s (target=$target)." >&2
        printf 'timeout\n' >"$timeout_marker"
        kill "$pid" >/dev/null 2>&1 || true
        sleep 2
        if kill -0 "$pid" >/dev/null 2>&1; then
          kill -9 "$pid" >/dev/null 2>&1 || true
        fi
      fi
    ) &
    timeout_pid="$!"
  fi

  set +e
  wait "$pid"
  code="$?"
  set -e

  if [ -n "$heartbeat_pid" ]; then
    kill "$heartbeat_pid" >/dev/null 2>&1 || true
    wait "$heartbeat_pid" >/dev/null 2>&1 || true
  fi

  if [ -n "$timeout_pid" ]; then
    kill "$timeout_pid" >/dev/null 2>&1 || true
    wait "$timeout_pid" >/dev/null 2>&1 || true
  fi

  if [ -n "$timeout_marker" ]; then
    if [ -s "$timeout_marker" ]; then
      code=124
    fi
    rm -f "$timeout_marker"
  fi

  return "$code"
}

if ! is_true "$HXHX_FORCE_STAGE0" && [ -d "$BOOTSTRAP_DIR" ] && [ -f "$BOOTSTRAP_DIR/dune" ]; then
  rm -rf "$BOOTSTRAP_BUILD_DIR"
  mkdir -p "$BOOTSTRAP_BUILD_DIR"
  (cd "$BOOTSTRAP_DIR" && tar --exclude="_build" --exclude="*.install" -cf - .) | (cd "$BOOTSTRAP_BUILD_DIR" && tar -xf -)
  echo "== Bootstrap build dir: $BOOTSTRAP_BUILD_DIR" >&2

  if find "$BOOTSTRAP_BUILD_DIR" -maxdepth 1 -type f -name "*.ml.parts" | grep -q .; then
    bash "$ROOT/scripts/hxhx/hydrate-bootstrap-shards.sh" "$BOOTSTRAP_BUILD_DIR" >&2
  fi

  (
    cd "$BOOTSTRAP_BUILD_DIR"
    if [ "$HXHX_BOOTSTRAP_HEARTBEAT" != "0" ] || [ "$HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS" != "0" ]; then
      echo "== Bootstrap dune watch: heartbeat=${HXHX_BOOTSTRAP_HEARTBEAT}s timeout=${HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS}s" >&2
    fi
    if [ "${HXHX_BOOTSTRAP_PREFER_NATIVE:-0}" = "1" ]; then
      if run_bootstrap_dune_build ./out.exe; then
        :
      else
        code="$?"
        if [ "$code" -eq 124 ]; then
          preserve_bootstrap_failure_artifacts "$BOOTSTRAP_BUILD_DIR" "./out.exe" "$code"
          exit "$code"
        fi
        if run_bootstrap_dune_build ./out.bc; then
          :
        else
          code="$?"
          preserve_bootstrap_failure_artifacts "$BOOTSTRAP_BUILD_DIR" "./out.bc" "$code"
          exit "$code"
        fi
      fi
    else
      if run_bootstrap_dune_build ./out.bc; then
        :
      else
        code="$?"
        if [ "$code" -eq 124 ]; then
          preserve_bootstrap_failure_artifacts "$BOOTSTRAP_BUILD_DIR" "./out.bc" "$code"
          exit "$code"
        fi
        if run_bootstrap_dune_build ./out.exe; then
          :
        else
          code="$?"
          preserve_bootstrap_failure_artifacts "$BOOTSTRAP_BUILD_DIR" "./out.exe" "$code"
          exit "$code"
        fi
      fi
    fi
  )

  BIN_EXE="$BOOTSTRAP_BUILD_DIR/_build/default/out.exe"
  BIN_BC="$BOOTSTRAP_BUILD_DIR/_build/default/out.bc"
  if [ -f "$BIN_EXE" ]; then
    echo "$BIN_EXE"
    exit 0
  fi
  if [ -f "$BIN_BC" ]; then
    echo "$BIN_BC"
    exit 0
  fi

  echo "Missing built executable: $BIN_EXE (native) or $BIN_BC (bytecode)" >&2
  exit 1
fi

if is_true "$HXHX_FORBID_STAGE0"; then
  if is_true "$HXHX_FORCE_STAGE0"; then
    echo "hxhx build: HXHX_FORBID_STAGE0=1 forbids HXHX_FORCE_STAGE0=1 (source lane delegates to stage0)." >&2
    exit 1
  fi
  echo "hxhx build: HXHX_FORBID_STAGE0=1 forbids stage0 source builds. Use committed bootstrap snapshots instead." >&2
  exit 1
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

resolved_haxe_connect="$HAXE_CONNECT"
repo_server_started_here=0

cpu_is_idle() {
  local cpu="${1:-}"
  if [ -z "$cpu" ]; then
    return 1
  fi
  awk -v c="$cpu" 'BEGIN { exit ((c + 0.0) < 1.0 ? 0 : 1) }'
}

read_repo_server_pid() {
  if [ "$HXHX_STAGE0_USE_REPO_SERVER" != "1" ]; then
    return 1
  fi
  if [ ! -x "$HAXE_SERVER_HELPER" ]; then
    return 1
  fi
  local status_line=""
  status_line="$("$HAXE_SERVER_HELPER" status 2>/dev/null || true)"
  case "$status_line" in
    running\ pid=*)
      printf '%s\n' "$status_line" | sed -E 's/^running pid=([0-9]+) .*$/\1/'
      return 0
      ;;
  esac
  return 1
}

read_repo_server_pids() {
  if [ "$HXHX_STAGE0_USE_REPO_SERVER" != "1" ]; then
    return 1
  fi
  if [ ! -x "$HAXE_SERVER_HELPER" ]; then
    return 1
  fi
  "$HAXE_SERVER_HELPER" owned-pids 2>/dev/null || true
}

read_pid_cpu_pct() {
  local pid="${1:-}"
  if [ -z "$pid" ]; then
    return 1
  fi
  ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ' || true
}

cleanup_repo_server() {
  if [ "$repo_server_started_here" = "1" ] && [ "$HXHX_STAGE0_KEEP_REPO_SERVER" != "1" ]; then
    if [ -x "$HAXE_SERVER_HELPER" ]; then
      "$HAXE_SERVER_HELPER" stop >/dev/null 2>&1 || true
    fi
  fi
}

cleanup_bootstrap_build_dir() {
  local status="${1:-0}"
  if [ "$BOOTSTRAP_BUILD_DIR_AUTOCREATED" != "1" ]; then
    return 0
  fi
  if [ "$status" -eq 0 ]; then
    rm -f "$BOOTSTRAP_BUILD_DIR/$BOOTSTRAP_BUILD_PID_FILE" 2>/dev/null || true
    return 0
  fi
  if [ "${HXHX_KEEP_TMP_ON_FAIL:-0}" = "1" ] || [ "${HXHX_KEEP_BOOTSTRAP_BUILD_DIR_ON_FAIL:-0}" = "1" ]; then
    echo "== bootstrap build dir retained after failure: $BOOTSTRAP_BUILD_DIR" >&2
    return 0
  fi
  rm -rf "$BOOTSTRAP_BUILD_DIR"
}

on_script_exit() {
  local status=$?
  cleanup_repo_server
  cleanup_bootstrap_build_dir "$status"
  exit "$status"
}

resolve_stage0_connect() {
  if [ -n "$resolved_haxe_connect" ]; then
    if [ "$HXHX_STAGE0_USE_REPO_SERVER" = "1" ]; then
      echo "== Stage0 source build: using explicit HAXE_CONNECT=$resolved_haxe_connect (helper opt-in ignored)." >&2
    fi
    return
  fi
  if [ "$HXHX_STAGE0_USE_REPO_SERVER" != "1" ]; then
    return
  fi
  if [ ! -x "$HAXE_SERVER_HELPER" ]; then
    echo "Missing helper script for HXHX_STAGE0_USE_REPO_SERVER=1: $HAXE_SERVER_HELPER" >&2
    exit 1
  fi
  if ! "$HAXE_SERVER_HELPER" status >/dev/null 2>&1; then
    "$HAXE_SERVER_HELPER" start >/dev/null
    repo_server_started_here=1
  fi
  resolved_haxe_connect="$("$HAXE_SERVER_HELPER" port)"
  echo "== Stage0 source build: using repo-owned haxe server --connect $resolved_haxe_connect" >&2
}

trap on_script_exit EXIT

if [ "$HXHX_KEEP_LOGS" = "1" ]; then
  echo "== Stage0 logs: retained (HXHX_KEEP_LOGS=1)" >&2
fi
if [ -n "$HXHX_LOG_DIR" ]; then
  echo "== Stage0 logs directory: $HXHX_LOG_DIR" >&2
fi

resolve_stage0_connect

(
  cd "$HXHX_DIR"
  build_mode="$HXHX_STAGE0_OCAML_BUILD"
  if [ "$HXHX_STAGE0_PREFER_NATIVE" = "1" ]; then
    build_mode="native"
  fi

  rm -rf "$STAGE0_OUT_DIR"
  mkdir -p "$STAGE0_OUT_DIR"

  haxe_args=()
  stage0_connect_stall_code=86

  resolve_stage0_reflaxe_src() {
    local candidate=""
    if [ -n "${HXHX_STAGE0_REFLAXE_SRC:-}" ] && [ -d "${HXHX_STAGE0_REFLAXE_SRC}" ]; then
      printf '%s\n' "${HXHX_STAGE0_REFLAXE_SRC}"
      return 0
    fi
    if command -v lix >/dev/null 2>&1; then
      candidate="$(lix run-haxelib path reflaxe 2>/dev/null | head -n 1 | tr -d '\r' || true)"
      if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
    if command -v haxelib >/dev/null 2>&1; then
      candidate="$(haxelib path reflaxe 2>/dev/null | head -n 1 | tr -d '\r' || true)"
      if [ -n "$candidate" ] && [ -d "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
    if [ -n "${HAXE_LIBCACHE:-}" ]; then
      candidate="${HAXE_LIBCACHE%/}/reflaxe/4.0.0-beta/haxelib/src"
      if [ -d "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
    echo "Failed to resolve reflaxe source path for HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY=1." >&2
    return 1
  }

  populate_haxe_args() {
    local mode="$1"
    if [ "$HXHX_STAGE0_SKIP_REFLAXE_NULL_SAFETY" = "1" ]; then
      local reflaxe_src=""
      reflaxe_src="$(resolve_stage0_reflaxe_src)"
      haxe_args=(
        -cp src
        -cp ../hxhx-core/src
        -main hxhx.Main
        --no-output
        -cp ../reflaxe.ocaml/src
        -cp ../reflaxe.ocaml/std
        -cp "$reflaxe_src"
        -D reflaxe=4.0.0-beta
        --macro 'reflaxe.ReflectCompiler.Start()'
        -D reflaxe.ocaml=0.14.0
        --macro 'reflaxe.ocaml.CompilerInit.Start()'
        -D no-traces
        -D no_traces
        -D ocaml_output=out
        -D reflaxe_ocaml
        -D ocaml_emit_only
      )
    else
      haxe_args=(build.hxml -D ocaml_emit_only)
    fi
    if [ "$STAGE0_OUT_DIR" != "$DEFAULT_STAGE0_OUT_DIR" ]; then
      haxe_args+=(-D "ocaml_output=$STAGE0_OUT_DIR")
    fi
    if [ "$HXHX_STAGE0_VERBOSE" = "1" ]; then
      haxe_args+=(-v)
    fi
    if [ -n "$resolved_haxe_connect" ]; then
      haxe_args+=(--connect "$resolved_haxe_connect")
    fi
    if [ "$HXHX_STAGE0_PROGRESS" = "1" ]; then
      haxe_args+=(-D reflaxe_ocaml_progress)
    fi
    if [ "$HXHX_STAGE0_TELEMETRY" = "1" ]; then
      haxe_args+=(-D reflaxe_ocaml_telemetry)
    fi
    if [ "$HXHX_STAGE0_TELEMETRY_DETAIL" = "1" ]; then
      haxe_args+=(-D reflaxe_ocaml_telemetry_detail)
    fi
    if [ -n "$HXHX_STAGE0_TELEMETRY_CLASS" ]; then
      haxe_args+=(-D "reflaxe_ocaml_telemetry_class=$HXHX_STAGE0_TELEMETRY_CLASS")
    fi
    if [ -n "$HXHX_STAGE0_TELEMETRY_FIELD" ]; then
      haxe_args+=(-D "reflaxe_ocaml_telemetry_field=$HXHX_STAGE0_TELEMETRY_FIELD")
    fi
    if [ "$HXHX_STAGE0_DISABLE_PREPASSES" = "1" ]; then
      haxe_args+=(-D reflaxe_ocaml_disable_expression_preprocessors)
    fi
    if [ "$HXHX_STAGE0_NO_EXPR_MACROS" = "1" ]; then
      haxe_args+=(-D hxhx_stage0_no_expr_macros)
    fi
    if [ "$HXHX_STAGE0_NO_EXTERNAL_MACRO_HOST" = "1" ]; then
      haxe_args+=(-D hxhx_stage0_no_external_macro_host)
    fi
    if [ "$HXHX_STAGE0_NO_INTERNAL_TOOLS" = "1" ]; then
      haxe_args+=(-D hxhx_stage0_no_internal_tools)
    fi
    if [ "$HXHX_STAGE0_NO_DISPLAY" = "1" ]; then
      haxe_args+=(-D hxhx_stage0_no_display)
    fi
    if [ "$HXHX_STAGE0_OCAML_ONLY" = "1" ]; then
      haxe_args+=(-D hxhx_stage0_ocaml_only)
    fi
    if [ "$HXHX_STAGE0_TIMES" = "1" ]; then
      haxe_args+=(--times)
    fi
    if [ "$HXHX_STAGE0_NO_INLINE" = "1" ]; then
      haxe_args+=(--no-inline)
    fi
    if [ "$HXHX_STAGE0_NO_OPT" = "1" ]; then
      haxe_args+=(--no-opt)
    fi
  }

  populate_haxe_args "$build_mode"

  run_stage0_build() {
    if [ "$HXHX_STAGE0_HEARTBEAT" = "0" ] && [ "$HXHX_STAGE0_FAILFAST_SECS" = "0" ]; then
      "$HAXE_BIN" "${haxe_args[@]}"
      return
    fi

    local log_file=""
    local pid=""
    local interval=""
    local start_hb=""
    local now=""
    local elapsed=""
    local tree_pids=""
    local tree_pid=""
    local rss_probe_pid=""
    local pid_rss_kb=""
    local rss_kb=""
    local tree_rss_kb=""
    local tree_rss_mb=""
    local rss_mb=""
    local cpu_pct=""
    local proc_state=""
    local log_bytes=""
    local heartbeat_suffix=""
    local connect_watch_enabled=0
    local connect_idle_started=0
    local connect_idle_elapsed=0
    local connect_log_static=0
    local last_log_bytes=""
    local client_idle=0
    local server_idle=0
    local repo_server_pid=""
    local repo_server_pids=""
    local repo_server_tree_pid=""
    local repo_server_cpu=""
    local repo_server_tree_cpu=""
    local repo_server_tree_rss_kb=0
    local repo_server_tree_rss_mb=0
    local repo_server_worker_pid=""
    local repo_server_worker_cpu=""
    local repo_server_worker_rss_kb=0
    local repo_server_pid_rss_kb=""
    local tree_cpu_pct=""
    local code=0

    log_file="$(create_stage0_log_file hxhx-stage0-build)"
    if [ "$HXHX_STAGE0_HEARTBEAT" = "0" ]; then
      interval=5
    else
      interval="$HXHX_STAGE0_HEARTBEAT"
    fi

    echo "== Stage0 build watch: heartbeat=${HXHX_STAGE0_HEARTBEAT}s failfast=${HXHX_STAGE0_FAILFAST_SECS}s" >&2
    echo "== Stage0 build command: $HAXE_BIN ${haxe_args[*]}" >&2
    echo "== Stage0 build log: $log_file" >&2
    "$HAXE_BIN" "${haxe_args[@]}" >"$log_file" 2>&1 &
    pid="$!"

    start_hb="$(date +%s)"
    if [ -n "$resolved_haxe_connect" ] && [ "$HXHX_STAGE0_CONNECT_IDLE_SECS" != "0" ]; then
      connect_watch_enabled=1
      repo_server_pid="$(read_repo_server_pid || true)"
      repo_server_pids="$(read_repo_server_pids || true)"
      if [ -n "$repo_server_pids" ]; then
        echo "== Stage0 connect watch: idle=${HXHX_STAGE0_CONNECT_IDLE_SECS}s endpoint=$resolved_haxe_connect server_pids=$(printf '%s' "$repo_server_pids" | tr '\n' ',')" >&2
      elif [ -n "$repo_server_pid" ]; then
        echo "== Stage0 connect watch: idle=${HXHX_STAGE0_CONNECT_IDLE_SECS}s endpoint=$resolved_haxe_connect server_pid=$repo_server_pid" >&2
      else
        echo "== Stage0 connect watch: idle=${HXHX_STAGE0_CONNECT_IDLE_SECS}s endpoint=$resolved_haxe_connect (server pid unavailable)" >&2
      fi
    fi

    while kill -0 "$pid" >/dev/null 2>&1; do
      sleep "$interval" || true
      now="$(date +%s)"
      elapsed="$((now - start_hb))"
      if [ -n "${HXHX_STAGE0_FAILFAST_SECS}" ] && [ "$HXHX_STAGE0_FAILFAST_SECS" != "0" ]; then
        if [ "$elapsed" -ge "$HXHX_STAGE0_FAILFAST_SECS" ]; then
          echo "Stage0 build exceeded failfast limit (${HXHX_STAGE0_FAILFAST_SECS}s). Killing pid=$pid." >&2
          kill -9 "$pid" >/dev/null 2>&1 || true
          echo "Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
          tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
          cleanup_stage0_log_file "$log_file"
          return 1
        fi
      fi

      tree_pids=""
      if [ "$connect_watch_enabled" = "1" ] || [ "$HXHX_STAGE0_HEARTBEAT" != "0" ]; then
        tree_pids="$(collect_process_tree_pids "$pid")"
      fi

      if [ "$connect_watch_enabled" = "1" ]; then
        log_bytes="$(wc -c <"$log_file" 2>/dev/null | tr -d ' ' || true)"
        if [ -n "$log_bytes" ] && [ -n "$last_log_bytes" ] && [ "$log_bytes" = "$last_log_bytes" ]; then
          connect_log_static=1
        else
          connect_log_static=0
        fi
        if [ -n "$log_bytes" ]; then
          last_log_bytes="$log_bytes"
        fi

        client_idle=1
        for tree_pid in $tree_pids; do
          tree_cpu_pct="$(read_pid_cpu_pct "$tree_pid")"
          if [ -z "$tree_cpu_pct" ]; then
            continue
          fi
          if ! cpu_is_idle "$tree_cpu_pct"; then
            client_idle=0
            break
          fi
        done

        repo_server_pids="$(read_repo_server_pids || true)"
        repo_server_pid="$(printf '%s\n' "$repo_server_pids" | awk 'NF { print; exit }')"
        server_idle=1
        repo_server_cpu=""
        repo_server_tree_cpu=""
        repo_server_tree_rss_kb=0
        repo_server_tree_rss_mb=0
        repo_server_worker_pid=""
        repo_server_worker_cpu=""
        repo_server_worker_rss_kb=0
        for repo_server_tree_pid in $repo_server_pids; do
          repo_server_cpu="$(read_pid_cpu_pct "$repo_server_tree_pid")"
          repo_server_pid_rss_kb="$(ps -o rss= -p "$repo_server_tree_pid" 2>/dev/null | tr -d ' ' || true)"
          if [ -n "$repo_server_cpu" ]; then
            repo_server_tree_cpu="$(awk -v total="${repo_server_tree_cpu:-0}" -v value="$repo_server_cpu" 'BEGIN { printf "%.1f", total + value }')"
            if ! cpu_is_idle "$repo_server_cpu"; then
              server_idle=0
            fi
            if [ -z "$repo_server_worker_cpu" ] || awk -v current="$repo_server_worker_cpu" -v candidate="$repo_server_cpu" 'BEGIN { exit (candidate > current ? 0 : 1) }'; then
              repo_server_worker_cpu="$repo_server_cpu"
              repo_server_worker_pid="$repo_server_tree_pid"
              repo_server_worker_rss_kb="${repo_server_pid_rss_kb:-0}"
            fi
          fi
          if [ -n "$repo_server_pid_rss_kb" ]; then
            repo_server_tree_rss_kb="$((repo_server_tree_rss_kb + repo_server_pid_rss_kb))"
            if [ -z "$repo_server_worker_pid" ] || { [ "${repo_server_worker_cpu:-0}" = "0.0" ] && [ "$repo_server_pid_rss_kb" -gt "$repo_server_worker_rss_kb" ]; }; then
              repo_server_worker_rss_kb="$repo_server_pid_rss_kb"
              repo_server_worker_pid="$repo_server_tree_pid"
            fi
          fi
        done
        if [ "$repo_server_tree_rss_kb" -gt 0 ]; then
          repo_server_tree_rss_mb="$((repo_server_tree_rss_kb / 1024))"
        fi
        if [ -z "$repo_server_pids" ]; then
          # Losing the verified server identity while the client is still
          # waiting is not evidence that the server is healthy and busy.
          server_idle=1
        elif [ -n "$repo_server_tree_cpu" ]; then
          repo_server_cpu="$repo_server_tree_cpu"
        fi

        if [ "$connect_log_static" = "1" ] && [ "$client_idle" = "1" ] && [ "$server_idle" = "1" ]; then
          if [ "$connect_idle_started" = "0" ]; then
            connect_idle_started="$now"
          fi
          connect_idle_elapsed="$((now - connect_idle_started))"
          if [ "$connect_idle_elapsed" -ge "$HXHX_STAGE0_CONNECT_IDLE_SECS" ]; then
            echo "Stage0 build appears stalled on --connect handoff (idle ${connect_idle_elapsed}s; log static)." >&2
            echo "Retrying once without --connect (set HXHX_STAGE0_CONNECT_IDLE_SECS=0 to disable this detector)." >&2
            kill "$pid" >/dev/null 2>&1 || true
            sleep 2
            if kill -0 "$pid" >/dev/null 2>&1; then
              kill -9 "$pid" >/dev/null 2>&1 || true
            fi
            echo "Last $HXHX_STAGE0_LOG_TAIL_LINES lines before retry:" >&2
            tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
            cleanup_stage0_log_file "$log_file"
            return "$stage0_connect_stall_code"
          fi
        else
          connect_idle_started=0
          connect_idle_elapsed=0
        fi
      fi

      if [ "$HXHX_STAGE0_HEARTBEAT" = "0" ]; then
        continue
      fi

      rss_probe_pid="$pid"
      rss_kb=""
      tree_rss_kb=0
      tree_rss_mb=0
      for tree_pid in $tree_pids; do
        pid_rss_kb="$(ps -o rss= -p "$tree_pid" 2>/dev/null | tr -d ' ' || true)"
        if [ -z "$pid_rss_kb" ]; then
          continue
        fi
        tree_rss_kb="$((tree_rss_kb + pid_rss_kb))"
        if [ -z "$rss_kb" ] || [ "$pid_rss_kb" -gt "$rss_kb" ]; then
          rss_kb="$pid_rss_kb"
          rss_probe_pid="$tree_pid"
        fi
      done
      if [ "$tree_rss_kb" -gt 0 ]; then
        tree_rss_mb="$((tree_rss_kb / 1024))"
      fi
      cpu_pct="$(ps -o %cpu= -p "$rss_probe_pid" 2>/dev/null | tr -d ' ' || true)"
      proc_state="$(ps -o state= -p "$rss_probe_pid" 2>/dev/null | tr -d ' ' || true)"
      log_bytes="$(wc -c <"$log_file" 2>/dev/null | tr -d ' ' || true)"
      heartbeat_suffix=""
      if [ -n "$cpu_pct" ]; then
        heartbeat_suffix="$heartbeat_suffix cpu=${cpu_pct}%"
      fi
      if [ -n "$proc_state" ]; then
        heartbeat_suffix="$heartbeat_suffix state=${proc_state}"
      fi
      if [ "$tree_rss_mb" != "0" ]; then
        heartbeat_suffix="$heartbeat_suffix tree_rss=${tree_rss_mb}MB"
      fi
      if [ -n "$log_bytes" ]; then
        heartbeat_suffix="$heartbeat_suffix log=${log_bytes}B"
      fi
      if [ -n "$repo_server_pid" ]; then
        heartbeat_suffix="$heartbeat_suffix server_pid=${repo_server_pid}"
      fi
      if [ -n "$repo_server_worker_pid" ]; then
        heartbeat_suffix="$heartbeat_suffix server_worker_pid=${repo_server_worker_pid}"
      fi
      if [ -n "$repo_server_cpu" ]; then
        heartbeat_suffix="$heartbeat_suffix server_tree_cpu=${repo_server_cpu}%"
      fi
      if [ "$repo_server_tree_rss_mb" != "0" ]; then
        heartbeat_suffix="$heartbeat_suffix server_tree_rss=${repo_server_tree_rss_mb}MB"
      fi
      if [ -n "$rss_kb" ]; then
        rss_mb="$((rss_kb / 1024))"
        if [ "$HXHX_STAGE0_MAX_RSS_MB" != "0" ] && [ "$tree_rss_mb" -ge "$HXHX_STAGE0_MAX_RSS_MB" ]; then
          echo "Stage0 build exceeded RSS cap (${HXHX_STAGE0_MAX_RSS_MB}MB). Killing pid=$pid." >&2
          kill -9 "$pid" >/dev/null 2>&1 || true
          echo "Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
          tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
          cleanup_stage0_log_file "$log_file"
          return 1
        fi
        echo "== Stage0 build heartbeat: elapsed=${elapsed}s rss=${rss_mb}MB pid=$pid focus=$rss_probe_pid$heartbeat_suffix" >&2
      else
        echo "== Stage0 build heartbeat: elapsed=${elapsed}s pid=$pid$heartbeat_suffix" >&2
      fi
      if [ -n "${HXHX_STAGE0_HEARTBEAT_TAIL_LINES}" ] && [ "$HXHX_STAGE0_HEARTBEAT_TAIL_LINES" != "0" ]; then
        if [ -s "$log_file" ]; then
          echo "== Stage0 build log tail (last $HXHX_STAGE0_HEARTBEAT_TAIL_LINES lines):" >&2
          tail -n "$HXHX_STAGE0_HEARTBEAT_TAIL_LINES" "$log_file" >&2 || true
        else
          echo "== Stage0 build log: (empty so far)" >&2
        fi
      fi
    done

    set +e
    wait "$pid"
    code="$?"
    set -e
    if [ "$code" != "0" ]; then
      echo "Stage0 build failed (exit=$code). Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
      tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
      cleanup_stage0_log_file "$log_file"
      return "$code"
    fi
    cleanup_stage0_log_file "$log_file"
  }

  sanitize_stage0_emit_dir() {
    local out_dir="$1"
    bash "$ROOT/scripts/hxhx/sanitize-stage3-emit-dir.sh" "$out_dir" >&2
  }

  run_stage0_source_lane() {
    local executable_name=""
    local target=""
    local code=0

    set +e
    run_stage0_build_with_connect_retry
    code="$?"
    set -e
    if [ "$code" != "0" ]; then
      return "$code"
    fi
    sanitize_stage0_emit_dir "$STAGE0_OUT_DIR"
    executable_name="$(stage0_executable_name)"
    target="./${executable_name}.bc"
    if [ "$build_mode" = "native" ]; then
      target="./${executable_name}.exe"
    fi
    (
      cd "$STAGE0_OUT_DIR"
      if [ "$HXHX_BOOTSTRAP_HEARTBEAT" != "0" ] || [ "$HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS" != "0" ]; then
        echo "== Stage0 dune watch: heartbeat=${HXHX_BOOTSTRAP_HEARTBEAT}s timeout=${HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS}s target=${target}" >&2
      fi
      run_bootstrap_dune_build "$target"
    )
  }

  run_stage0_build_with_connect_retry() {
    local code=0
    set +e
    run_stage0_build
    code="$?"
    set -e
    if [ "$code" -eq "$stage0_connect_stall_code" ] && [ -n "$resolved_haxe_connect" ]; then
      echo "== Stage0 build: rerunning once without --connect after idle-handoff detection." >&2
      resolved_haxe_connect=""
      populate_haxe_args "$build_mode"
      set +e
      run_stage0_build
      code="$?"
      set -e
    fi
    return "$code"
  }

  if ! run_stage0_source_lane; then
    if [ "$build_mode" = "native" ]; then
      echo "hxhx stage0 build: native failed; retrying bytecode (expected on some platforms; set HXHX_STAGE0_OCAML_BUILD=byte to skip native attempts)." >&2
      build_mode="byte"
      rm -rf "$STAGE0_OUT_DIR"
      mkdir -p "$STAGE0_OUT_DIR"
      populate_haxe_args "$build_mode"
      run_stage0_source_lane
    else
      exit 1
    fi
  fi
)

STAGE0_EXECUTABLE_NAME="$(stage0_executable_name)"
BIN_EXE="$STAGE0_OUT_DIR/_build/default/${STAGE0_EXECUTABLE_NAME}.exe"
BIN_BC="$STAGE0_OUT_DIR/_build/default/${STAGE0_EXECUTABLE_NAME}.bc"
if [ -f "$BIN_EXE" ]; then
  echo "$BIN_EXE"
  exit 0
fi
if [ -f "$BIN_BC" ]; then
  echo "$BIN_BC"
  exit 0
fi

echo "Missing built executable: $BIN_EXE (native) or $BIN_BC (bytecode)" >&2
exit 1
