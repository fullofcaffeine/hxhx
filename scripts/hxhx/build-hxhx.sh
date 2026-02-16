#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXE_CONNECT="${HAXE_CONNECT:-}"
HXHX_FORCE_STAGE0="${HXHX_FORCE_STAGE0:-}"
HXHX_STAGE0_PROGRESS="${HXHX_STAGE0_PROGRESS:-0}"
HXHX_STAGE0_PROFILE="${HXHX_STAGE0_PROFILE:-0}"
HXHX_STAGE0_PROFILE_DETAIL="${HXHX_STAGE0_PROFILE_DETAIL:-0}"
HXHX_STAGE0_PROFILE_CLASS="${HXHX_STAGE0_PROFILE_CLASS:-}"
HXHX_STAGE0_PROFILE_FIELD="${HXHX_STAGE0_PROFILE_FIELD:-}"
HXHX_STAGE0_OCAML_BUILD="${HXHX_STAGE0_OCAML_BUILD:-byte}"
HXHX_STAGE0_PREFER_NATIVE="${HXHX_STAGE0_PREFER_NATIVE:-0}"
HXHX_STAGE0_TIMES="${HXHX_STAGE0_TIMES:-0}"
HXHX_STAGE0_VERBOSE="${HXHX_STAGE0_VERBOSE:-0}"
HXHX_STAGE0_DISABLE_PREPASSES="${HXHX_STAGE0_DISABLE_PREPASSES:-0}"
HXHX_STAGE0_HEARTBEAT="${HXHX_STAGE0_HEARTBEAT:-0}"
HXHX_STAGE0_LOG_TAIL_LINES="${HXHX_STAGE0_LOG_TAIL_LINES:-80}"
HXHX_STAGE0_FAILFAST_SECS="${HXHX_STAGE0_FAILFAST_SECS:-900}"
HXHX_STAGE0_HEARTBEAT_TAIL_LINES="${HXHX_STAGE0_HEARTBEAT_TAIL_LINES:-0}"
HXHX_KEEP_LOGS="${HXHX_KEEP_LOGS:-0}"
HXHX_LOG_DIR="${HXHX_LOG_DIR:-}"
HXHX_BOOTSTRAP_HEARTBEAT="${HXHX_BOOTSTRAP_HEARTBEAT:-20}"
HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS="${HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HXHX_DIR="$ROOT/packages/hxhx"
BOOTSTRAP_DIR="$HXHX_DIR/bootstrap_out"
BOOTSTRAP_BUILD_DIR="${HXHX_BOOTSTRAP_BUILD_DIR:-$HXHX_DIR/bootstrap_work}"

create_stage0_log_file() {
  local prefix="$1"
  if [ -n "$HXHX_LOG_DIR" ]; then
    mkdir -p "$HXHX_LOG_DIR"
    mktemp "$HXHX_LOG_DIR/${prefix}.XXXXXX.log"
    return
  fi
  mktemp -t "${prefix}.XXXXXX.log"
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

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx build: dune/ocamlc not found on PATH." >&2
  exit 0
fi

if [ ! -d "$HXHX_DIR" ]; then
  echo "Missing hxhx package directory: $HXHX_DIR" >&2
  exit 1
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

if [ -z "$HXHX_FORCE_STAGE0" ] && [ -d "$BOOTSTRAP_DIR" ] && [ -f "$BOOTSTRAP_DIR/dune" ]; then
  rm -rf "$BOOTSTRAP_BUILD_DIR"
  mkdir -p "$BOOTSTRAP_BUILD_DIR"
  (cd "$BOOTSTRAP_DIR" && tar --exclude="_build" --exclude="*.install" -cf - .) | (cd "$BOOTSTRAP_BUILD_DIR" && tar -xf -)

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
          exit "$code"
        fi
        run_bootstrap_dune_build ./out.bc
      fi
    else
      if run_bootstrap_dune_build ./out.bc; then
        :
      else
        code="$?"
        if [ "$code" -eq 124 ]; then
          exit "$code"
        fi
        run_bootstrap_dune_build ./out.exe
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

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi
if [ "$HXHX_KEEP_LOGS" = "1" ]; then
  echo "== Stage0 logs: retained (HXHX_KEEP_LOGS=1)" >&2
fi
if [ -n "$HXHX_LOG_DIR" ]; then
  echo "== Stage0 logs directory: $HXHX_LOG_DIR" >&2
fi

(
  cd "$HXHX_DIR"
  build_mode="$HXHX_STAGE0_OCAML_BUILD"
  if [ "$HXHX_STAGE0_PREFER_NATIVE" = "1" ]; then
    build_mode="native"
  fi

  rm -rf out
  mkdir -p out

  haxe_args=(build.hxml -D "ocaml_build=$build_mode")
  if [ "$HXHX_STAGE0_VERBOSE" = "1" ]; then
    haxe_args+=(-v)
  fi
  if [ -n "$HAXE_CONNECT" ]; then
    haxe_args+=(--connect "$HAXE_CONNECT")
  fi
  if [ "$HXHX_STAGE0_PROGRESS" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_progress)
  fi
  if [ "$HXHX_STAGE0_PROFILE" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_profile)
  fi
  if [ "$HXHX_STAGE0_PROFILE_DETAIL" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_profile_detail)
  fi
  if [ -n "$HXHX_STAGE0_PROFILE_CLASS" ]; then
    haxe_args+=(-D "reflaxe_ocaml_profile_class=$HXHX_STAGE0_PROFILE_CLASS")
  fi
  if [ -n "$HXHX_STAGE0_PROFILE_FIELD" ]; then
    haxe_args+=(-D "reflaxe_ocaml_profile_field=$HXHX_STAGE0_PROFILE_FIELD")
  fi
  if [ "$HXHX_STAGE0_DISABLE_PREPASSES" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_disable_expression_preprocessors)
  fi
  if [ "$HXHX_STAGE0_TIMES" = "1" ]; then
    haxe_args+=(--times)
  fi

  run_stage0_build() {
    if [ "$HXHX_STAGE0_HEARTBEAT" = "0" ]; then
      "$HAXE_BIN" "${haxe_args[@]}"
      return
    fi

    log_file="$(create_stage0_log_file hxhx-stage0-build)"
    echo "== Stage0 build command: $HAXE_BIN ${haxe_args[*]}" >&2
    echo "== Stage0 build log: $log_file" >&2
    "$HAXE_BIN" "${haxe_args[@]}" >"$log_file" 2>&1 &
    pid="$!"

    interval="$HXHX_STAGE0_HEARTBEAT"
    start_hb="$(date +%s)"
    while kill -0 "$pid" >/dev/null 2>&1; do
      sleep "$interval" || true
      now="$(date +%s)"
      child_pid="$(pgrep -P "$pid" | head -n 1 || true)"
      if [ -n "${HXHX_STAGE0_FAILFAST_SECS}" ] && [ "$HXHX_STAGE0_FAILFAST_SECS" != "0" ]; then
        elapsed="$((now - start_hb))"
        if [ "$elapsed" -ge "$HXHX_STAGE0_FAILFAST_SECS" ]; then
          echo "Stage0 build exceeded failfast limit (${HXHX_STAGE0_FAILFAST_SECS}s). Killing pid=$pid." >&2
          kill -9 "$pid" >/dev/null 2>&1 || true
          echo "Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
          tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
          cleanup_stage0_log_file "$log_file"
          exit 1
        fi
      fi
      rss_probe_pid="$pid"
      if [ -n "$child_pid" ]; then
        rss_probe_pid="$child_pid"
      fi
      rss_kb="$(ps -o rss= -p "$rss_probe_pid" 2>/dev/null | tr -d ' ' || true)"
      if [ -n "$rss_kb" ]; then
        rss_mb="$((rss_kb / 1024))"
        if [ -n "$child_pid" ]; then
          echo "== Stage0 build heartbeat: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid child=$child_pid" >&2
        else
          echo "== Stage0 build heartbeat: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid" >&2
        fi
      else
        if [ -n "$child_pid" ]; then
          echo "== Stage0 build heartbeat: elapsed=$((now - start_hb))s pid=$pid child=$child_pid" >&2
        else
          echo "== Stage0 build heartbeat: elapsed=$((now - start_hb))s pid=$pid" >&2
        fi
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
      exit "$code"
    fi
    cleanup_stage0_log_file "$log_file"
  }

  if ! run_stage0_build; then
    if [ "$build_mode" = "native" ]; then
      echo "hxhx stage0 build: native failed; retrying bytecode (expected on some platforms; set HXHX_STAGE0_OCAML_BUILD=byte to skip native attempts)." >&2
      build_mode="byte"
      rm -rf out
      mkdir -p out
      haxe_args=(build.hxml -D "ocaml_build=$build_mode")
      if [ "$HXHX_STAGE0_VERBOSE" = "1" ]; then
        haxe_args+=(-v)
      fi
      if [ -n "$HAXE_CONNECT" ]; then
        haxe_args+=(--connect "$HAXE_CONNECT")
      fi
      if [ "$HXHX_STAGE0_PROGRESS" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_progress)
      fi
      if [ "$HXHX_STAGE0_PROFILE" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_profile)
      fi
      if [ "$HXHX_STAGE0_PROFILE_DETAIL" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_profile_detail)
      fi
      if [ -n "$HXHX_STAGE0_PROFILE_CLASS" ]; then
        haxe_args+=(-D "reflaxe_ocaml_profile_class=$HXHX_STAGE0_PROFILE_CLASS")
      fi
      if [ -n "$HXHX_STAGE0_PROFILE_FIELD" ]; then
        haxe_args+=(-D "reflaxe_ocaml_profile_field=$HXHX_STAGE0_PROFILE_FIELD")
      fi
      if [ "$HXHX_STAGE0_DISABLE_PREPASSES" = "1" ]; then
        haxe_args+=(-D reflaxe_ocaml_disable_expression_preprocessors)
      fi
      if [ "$HXHX_STAGE0_TIMES" = "1" ]; then
        haxe_args+=(--times)
      fi
      run_stage0_build
    else
      exit 1
    fi
  fi
)

BIN_EXE="$HXHX_DIR/out/_build/default/out.exe"
BIN_BC="$HXHX_DIR/out/_build/default/out.bc"
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
