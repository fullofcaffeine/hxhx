#!/usr/bin/env bash
set -euo pipefail

# Regenerate the committed bootstrap snapshot for `hxhx` itself.
#
# Why
# - CI/Gate runners should be able to build `hxhx` without requiring a stage0 `haxe` binary.
# - We achieve this by committing a generated OCaml snapshot under `packages/hxhx/bootstrap_out`
#   and building it with `dune`.
#
# What
# - Emits `packages/hxhx` via stage0 `haxe` + `reflaxe.ocaml` (emit-only; no dune build).
# - Copies the generated OCaml sources (excluding `_build/` and `_gen_hx/`) into:
#     packages/hxhx/bootstrap_out/
# - Automatically shards oversized generated OCaml units into deterministic
#   `<Module>.ml.partNNN` chunk files + `<Module>.ml.parts` manifests to avoid tracked files above
#   GitHub's 50MB warning threshold.
#
# Notes
# - Maintainer-only script: it requires stage0 `haxe`.
# - Do not edit files inside `packages/hxhx/bootstrap_out/` by hand.

usage() {
  cat <<'USAGE'
Usage: bash scripts/hxhx/regenerate-hxhx-bootstrap.sh [options]

Options:
  --fast         Local iteration mode. Defaults to incremental emit and skips snapshot verify.
  --full         Full deterministic mode (default): clean emit output and verify snapshot build.
  --incremental  Reuse existing packages/hxhx/out before stage0 emit (faster local loop).
  --clean-out    Clean packages/hxhx/out before stage0 emit.
  --no-verify    Skip bootstrap snapshot verify build.
  --verify       Run bootstrap snapshot verify build.
  --server-preflight         Check for stale haxe --wait/--server-connect processes before emit (default).
  --no-server-preflight      Skip stale haxe server preflight checks.
  --kill-stale-haxe-servers  In preflight, terminate stale haxe server processes before emit.
  --diag-every <seconds>     When heartbeat is disabled, print periodic stage0 diagnostics.
  -h, --help     Show this help.

Environment knobs (all optional):
  HXHX_BOOTSTRAP_FAST=1       Same effect as --fast.
  HXHX_BOOTSTRAP_CLEAN_OUT=0  Reuse packages/hxhx/out (incremental).
  HXHX_BOOTSTRAP_VERIFY=0     Skip verify step.
  HXHX_HAXE_SERVER_PREFLIGHT=1  Enable stale haxe server preflight.
  HXHX_KILL_STALE_HAXE_SERVERS=1  Kill stale haxe servers in preflight.
  HXHX_STAGE0_DIAG_EVERY=30   Diagnostics cadence when heartbeat is disabled.
USAGE
}

assert_bool_01() {
  local name="$1"
  local value="$2"
  case "$value" in
    0|1) ;;
    *)
      echo "Invalid value for $name: '$value' (expected 0 or 1)." >&2
      exit 1
      ;;
  esac
}

assert_non_negative_int() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "Invalid value for $name: '$value' (expected a non-negative integer)." >&2
      exit 1
      ;;
    *)
      ;;
  esac
}

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXE_CONNECT="${HAXE_CONNECT:-}"
HXHX_BOOTSTRAP_DEBUG="${HXHX_BOOTSTRAP_DEBUG:-0}"
HXHX_STAGE0_PROGRESS="${HXHX_STAGE0_PROGRESS:-0}"
HXHX_STAGE0_PROFILE="${HXHX_STAGE0_PROFILE:-0}"
HXHX_STAGE0_PROFILE_DETAIL="${HXHX_STAGE0_PROFILE_DETAIL:-0}"
HXHX_STAGE0_PROFILE_CLASS="${HXHX_STAGE0_PROFILE_CLASS:-}"
HXHX_STAGE0_PROFILE_FIELD="${HXHX_STAGE0_PROFILE_FIELD:-}"
HXHX_STAGE0_VERBOSE="${HXHX_STAGE0_VERBOSE:-0}"
HXHX_STAGE0_DISABLE_PREPASSES="${HXHX_STAGE0_DISABLE_PREPASSES:-0}"
HXHX_STAGE0_HEARTBEAT="${HXHX_STAGE0_HEARTBEAT:-20}"
HXHX_STAGE0_LOG_TAIL_LINES="${HXHX_STAGE0_LOG_TAIL_LINES:-80}"
HXHX_STAGE0_FAILFAST_SECS="${HXHX_STAGE0_FAILFAST_SECS:-900}"
HXHX_STAGE0_HEARTBEAT_TAIL_LINES="${HXHX_STAGE0_HEARTBEAT_TAIL_LINES:-0}"
HXHX_KEEP_LOGS="${HXHX_KEEP_LOGS:-0}"
HXHX_LOG_DIR="${HXHX_LOG_DIR:-}"
HXHX_BOOTSTRAP_FAST="${HXHX_BOOTSTRAP_FAST:-0}"
HXHX_BOOTSTRAP_CLEAN_OUT="${HXHX_BOOTSTRAP_CLEAN_OUT:-}"
HXHX_BOOTSTRAP_VERIFY="${HXHX_BOOTSTRAP_VERIFY:-}"
HXHX_HAXE_SERVER_PREFLIGHT="${HXHX_HAXE_SERVER_PREFLIGHT:-1}"
HXHX_KILL_STALE_HAXE_SERVERS="${HXHX_KILL_STALE_HAXE_SERVERS:-0}"
HXHX_STAGE0_DIAG_EVERY="${HXHX_STAGE0_DIAG_EVERY:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --fast)
      HXHX_BOOTSTRAP_FAST=1
      ;;
    --full)
      HXHX_BOOTSTRAP_FAST=0
      ;;
    --incremental)
      HXHX_BOOTSTRAP_CLEAN_OUT=0
      ;;
    --clean-out)
      HXHX_BOOTSTRAP_CLEAN_OUT=1
      ;;
    --no-verify)
      HXHX_BOOTSTRAP_VERIFY=0
      ;;
    --verify)
      HXHX_BOOTSTRAP_VERIFY=1
      ;;
    --server-preflight)
      HXHX_HAXE_SERVER_PREFLIGHT=1
      ;;
    --no-server-preflight)
      HXHX_HAXE_SERVER_PREFLIGHT=0
      ;;
    --kill-stale-haxe-servers)
      HXHX_KILL_STALE_HAXE_SERVERS=1
      ;;
    --diag-every)
      shift
      if [ $# -eq 0 ]; then
        echo "Missing value for --diag-every" >&2
        exit 1
      fi
      HXHX_STAGE0_DIAG_EVERY="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

assert_bool_01 "HXHX_BOOTSTRAP_FAST" "$HXHX_BOOTSTRAP_FAST"
if [ -z "$HXHX_BOOTSTRAP_CLEAN_OUT" ]; then
  HXHX_BOOTSTRAP_CLEAN_OUT="$([ "$HXHX_BOOTSTRAP_FAST" = "1" ] && echo 0 || echo 1)"
fi
if [ -z "$HXHX_BOOTSTRAP_VERIFY" ]; then
  HXHX_BOOTSTRAP_VERIFY="$([ "$HXHX_BOOTSTRAP_FAST" = "1" ] && echo 0 || echo 1)"
fi
assert_bool_01 "HXHX_BOOTSTRAP_CLEAN_OUT" "$HXHX_BOOTSTRAP_CLEAN_OUT"
assert_bool_01 "HXHX_BOOTSTRAP_VERIFY" "$HXHX_BOOTSTRAP_VERIFY"
assert_bool_01 "HXHX_HAXE_SERVER_PREFLIGHT" "$HXHX_HAXE_SERVER_PREFLIGHT"
assert_bool_01 "HXHX_KILL_STALE_HAXE_SERVERS" "$HXHX_KILL_STALE_HAXE_SERVERS"
assert_non_negative_int "HXHX_STAGE0_DIAG_EVERY" "$HXHX_STAGE0_DIAG_EVERY"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="$ROOT/packages/hxhx"
OUT_DIR="$PKG_DIR/out"
BOOTSTRAP_DIR="$PKG_DIR/bootstrap_out"
BOOTSTRAP_VERIFY_DIR="${HXHX_BOOTSTRAP_VERIFY_DIR:-$PKG_DIR/bootstrap_verify}"

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
    echo "== Stage0 emit log retained: $path"
  else
    rm -f "$path"
  fi
}

list_haxe_server_pids() {
  ps -axo pid=,command= | awk '
    {
      pid = $1
      $1 = ""
      cmd = substr($0, 2)
      if (cmd ~ /haxe/ && (cmd ~ /--wait([[:space:]]|$)/ || cmd ~ /--server-connect([[:space:]]|$)/))
        print pid
    }
  ' | sort -u
}

print_haxe_server_processes() {
  local pids="$1"
  if [ -z "$pids" ]; then
    return
  fi
  local ps_pids
  ps_pids="$(printf '%s\n' "$pids" | paste -sd, -)"
  if [ -z "$ps_pids" ]; then
    return
  fi
  ps -o pid=,etime=,rss=,command= -p "$ps_pids" 2>/dev/null || true
}

run_haxe_server_preflight() {
  if [ "$HXHX_HAXE_SERVER_PREFLIGHT" != "1" ]; then
    echo "== Haxe server preflight: skipped (HXHX_HAXE_SERVER_PREFLIGHT=0)"
    return
  fi

  local pids
  pids="$(list_haxe_server_pids)"
  if [ -z "$pids" ]; then
    echo "== Haxe server preflight: no stale haxe --wait/--server-connect processes detected"
    return
  fi

  local count
  count="$(printf '%s\n' "$pids" | sed '/^$/d' | wc -l | tr -d ' ')"
  echo "== Haxe server preflight: found $count existing haxe server process(es):"
  print_haxe_server_processes "$pids"

  if [ "$HXHX_KILL_STALE_HAXE_SERVERS" != "1" ]; then
    echo "== Haxe server preflight: not terminating by default."
    echo "   Use --kill-stale-haxe-servers (or HXHX_KILL_STALE_HAXE_SERVERS=1) to auto-clean."
    return
  fi

  echo "== Haxe server preflight: terminating stale haxe server process(es)"
  # shellcheck disable=SC2086
  kill $pids >/dev/null 2>&1 || true
  sleep 1
  local remaining
  remaining="$(list_haxe_server_pids)"
  if [ -n "$remaining" ]; then
    echo "== Haxe server preflight: forcing kill for remaining process(es)"
    # shellcheck disable=SC2086
    kill -9 $remaining >/dev/null 2>&1 || true
    sleep 1
  fi

  local after
  after="$(list_haxe_server_pids)"
  if [ -n "$after" ]; then
    local after_count
    after_count="$(printf '%s\n' "$after" | sed '/^$/d' | wc -l | tr -d ' ')"
    echo "== Haxe server preflight: warning - $after_count process(es) still present after cleanup attempt:"
    print_haxe_server_processes "$after"
  else
    echo "== Haxe server preflight: stale haxe server process cleanup complete"
  fi
}

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Missing dune/ocamlc on PATH." >&2
  exit 1
fi

if [ ! -d "$PKG_DIR" ]; then
  echo "Missing package directory: $PKG_DIR" >&2
  exit 1
fi

echo "== Regenerating hxhx via stage0 (this requires Haxe + reflaxe.ocaml)"
if [ "$HXHX_BOOTSTRAP_FAST" = "1" ]; then
  echo "== Mode: fast (clean_out=${HXHX_BOOTSTRAP_CLEAN_OUT}, verify=${HXHX_BOOTSTRAP_VERIFY})"
else
  echo "== Mode: full (clean_out=${HXHX_BOOTSTRAP_CLEAN_OUT}, verify=${HXHX_BOOTSTRAP_VERIFY})"
fi
if [ -z "${HXHX_STAGE0_HEARTBEAT}" ] || [ "$HXHX_STAGE0_HEARTBEAT" = "0" ]; then
  echo "== Stage0 heartbeat: disabled (set HXHX_STAGE0_HEARTBEAT=<seconds> to enable)"
else
  echo "== Stage0 heartbeat: every ${HXHX_STAGE0_HEARTBEAT}s (set HXHX_STAGE0_HEARTBEAT=0 to disable)"
fi
if [ -n "${HXHX_STAGE0_FAILFAST_SECS}" ] && [ "$HXHX_STAGE0_FAILFAST_SECS" != "0" ]; then
  echo "== Stage0 failfast: ${HXHX_STAGE0_FAILFAST_SECS}s"
else
  echo "== Stage0 failfast: disabled"
fi
if [ "$HXHX_KEEP_LOGS" = "1" ]; then
  echo "== Stage0 logs: retained (HXHX_KEEP_LOGS=1)"
fi
if [ -n "$HXHX_LOG_DIR" ]; then
  echo "== Stage0 logs directory: $HXHX_LOG_DIR"
fi
if [ "$HXHX_STAGE0_DIAG_EVERY" != "0" ]; then
  echo "== Stage0 disabled-heartbeat diagnostics: every ${HXHX_STAGE0_DIAG_EVERY}s"
fi

run_haxe_server_preflight

start_ts="$(date +%s)"
(
  # We only need the emitted OCaml sources for the snapshot. Running the full OCaml build step
  # (dune/ocamlopt) here is redundant, and it can make snapshot refreshes significantly slower.
  #
  # `-D ocaml_emit_only` keeps stage0 as a codegen oracle while preserving the "stage0-free build"
  # property for everyone else via the committed snapshot + dune build in CI.
  cd "$PKG_DIR"
  if [ "$HXHX_BOOTSTRAP_CLEAN_OUT" = "1" ]; then
    rm -rf out
  fi
  mkdir -p out
  haxe_args=(build.hxml -D ocaml_emit_only)
  if [ "$HXHX_STAGE0_VERBOSE" = "1" ]; then
    haxe_args+=(-v)
  fi
  if [ -n "$HAXE_CONNECT" ]; then
    haxe_args+=(--connect "$HAXE_CONNECT")
  fi
  if [ "$HXHX_STAGE0_DISABLE_PREPASSES" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_disable_expression_preprocessors)
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

  # `--times` prints only at the end; keep it enabled in debug mode so maintainers can
  # see where stage0 is spending time.
  if [ "$HXHX_STAGE0_PROGRESS" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_progress)
  fi
  if [ "$HXHX_STAGE0_PROFILE" = "1" ]; then
    haxe_args+=(-D reflaxe_ocaml_profile)
  fi
  if [ "$HXHX_BOOTSTRAP_DEBUG" = "1" ]; then
    haxe_args+=(--times)
  fi

  run_stage0_emit() {
    log_file="$(create_stage0_log_file hxhx-stage0-emit)"
    echo "== Stage0 emit command: $HAXE_BIN ${haxe_args[*]}"
    echo "== Stage0 emit log: $log_file"
    pid=""
    "$HAXE_BIN" "${haxe_args[@]}" >"$log_file" 2>&1 &
    pid="$!"

    interval="0"
    status_mode="none"
    if [ -n "${HXHX_STAGE0_HEARTBEAT}" ] && [ "$HXHX_STAGE0_HEARTBEAT" != "0" ]; then
      interval="$HXHX_STAGE0_HEARTBEAT"
      status_mode="heartbeat"
    elif [ "$HXHX_STAGE0_DIAG_EVERY" != "0" ]; then
      interval="$HXHX_STAGE0_DIAG_EVERY"
      status_mode="diag"
      echo "== Stage0 emit diagnostics: heartbeat disabled; reporting every ${interval}s"
    else
      echo "== Stage0 emit diagnostics: heartbeat disabled and diag polling off."
      echo "== To inspect progress manually: tail -f \"$log_file\""
    fi

    start_hb="$(date +%s)"
    last_status_ts="$start_hb"
    while kill -0 "$pid" >/dev/null 2>&1; do
      sleep 1 || true
      now="$(date +%s)"
      if [ -n "${HXHX_STAGE0_FAILFAST_SECS}" ] && [ "$HXHX_STAGE0_FAILFAST_SECS" != "0" ]; then
        elapsed="$((now - start_hb))"
        if [ "$elapsed" -ge "$HXHX_STAGE0_FAILFAST_SECS" ]; then
          echo "Stage0 emit exceeded failfast limit (${HXHX_STAGE0_FAILFAST_SECS}s). Killing pid=$pid." >&2
          kill -9 "$pid" >/dev/null 2>&1 || true
          echo "Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
          tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
          cleanup_stage0_log_file "$log_file"
          exit 1
        fi
      fi
      if [ "$interval" = "0" ]; then
        continue
      fi
      if [ "$((now - last_status_ts))" -lt "$interval" ]; then
        continue
      fi
      last_status_ts="$now"

      child_pid="$(pgrep -P "$pid" | head -n 1 || true)"
      rss_probe_pid="$pid"
      if [ -n "$child_pid" ]; then
        rss_probe_pid="$child_pid"
      fi
      rss_kb="$(ps -o rss= -p "$rss_probe_pid" 2>/dev/null | tr -d ' ' || true)"
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
      if [ -n "$log_bytes" ]; then
        heartbeat_suffix="$heartbeat_suffix log=${log_bytes}B"
      fi
      if [ -n "$rss_kb" ]; then
        rss_mb="$((rss_kb / 1024))"
        if [ -n "$child_pid" ]; then
          echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid child=$child_pid$heartbeat_suffix"
        else
          echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid$heartbeat_suffix"
        fi
      else
        if [ -n "$child_pid" ]; then
          echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s pid=$pid child=$child_pid$heartbeat_suffix"
        else
          echo "== Stage0 emit ${status_mode}: elapsed=$((now - start_hb))s pid=$pid$heartbeat_suffix"
        fi
      fi
      if [ -n "${HXHX_STAGE0_HEARTBEAT_TAIL_LINES}" ] && [ "$HXHX_STAGE0_HEARTBEAT_TAIL_LINES" != "0" ]; then
        if [ -s "$log_file" ]; then
          echo "== Stage0 emit log tail (last $HXHX_STAGE0_HEARTBEAT_TAIL_LINES lines):"
          tail -n "$HXHX_STAGE0_HEARTBEAT_TAIL_LINES" "$log_file" || true
        else
          echo "== Stage0 emit log: (empty so far)"
        fi
      fi
    done

    if [ -z "$pid" ]; then
      echo "Stage0 emit internal error: missing pid for stage0 process." >&2
      exit 1
    fi

    set +e
    wait "$pid"
    code="$?"
    set -e
    if [ "$code" != "0" ]; then
      echo "Stage0 emit failed (exit=$code). Last $HXHX_STAGE0_LOG_TAIL_LINES lines:" >&2
      tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" >&2 || true
      cleanup_stage0_log_file "$log_file"
      exit "$code"
    fi

    if [ "$HXHX_BOOTSTRAP_DEBUG" = "1" ]; then
      echo "== Stage0 emit completed; last $HXHX_STAGE0_LOG_TAIL_LINES lines:"
      tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" || true
    fi
    cleanup_stage0_log_file "$log_file"
  }

  run_stage0_emit
)
end_ts="$(date +%s)"
echo "== Stage0 emit duration: $((end_ts - start_ts))s"

if [ ! -d "$OUT_DIR" ]; then
  echo "Missing generated output directory: $OUT_DIR" >&2
  exit 1
fi

echo "== Updating bootstrap snapshot: $BOOTSTRAP_DIR"
copy_start_ts="$(date +%s)"
rm -rf "$BOOTSTRAP_DIR"
mkdir -p "$BOOTSTRAP_DIR"

# Copy everything except build artifacts and generator sources.
(cd "$OUT_DIR" && tar --exclude='_build' --exclude='_gen_hx' -cf - .) | (cd "$BOOTSTRAP_DIR" && tar -xf -)

echo "== Sharding oversized bootstrap OCaml units (max ${HXHX_BOOTSTRAP_SHARD_MAX_BYTES:-50000000}B)"
bash "$ROOT/scripts/hxhx/shard-bootstrap-ml.sh" "$BOOTSTRAP_DIR"

copy_end_ts="$(date +%s)"
bootstrap_files="$(find "$BOOTSTRAP_DIR" -type f | wc -l | tr -d ' ')"
echo "== Bootstrap snapshot copy duration: $((copy_end_ts - copy_start_ts))s (files=$bootstrap_files)"

if [ "$HXHX_BOOTSTRAP_VERIFY" = "1" ]; then
  echo "== Verifying bootstrap snapshot builds (hydrate + dune)"
  verify_start_ts="$(date +%s)"
  rm -rf "$BOOTSTRAP_VERIFY_DIR"
  mkdir -p "$BOOTSTRAP_VERIFY_DIR"
  (cd "$BOOTSTRAP_DIR" && tar --exclude="_build" --exclude="*.install" -cf - .) | (cd "$BOOTSTRAP_VERIFY_DIR" && tar -xf -)
  if find "$BOOTSTRAP_VERIFY_DIR" -maxdepth 1 -type f -name "*.ml.parts" | grep -q .; then
    bash "$ROOT/scripts/hxhx/hydrate-bootstrap-shards.sh" "$BOOTSTRAP_VERIFY_DIR"
  fi
  (
    cd "$BOOTSTRAP_VERIFY_DIR"
    # NOTE: On some platforms (notably macOS/arm64), extremely large generated compilation units
    # can cause native `ocamlopt` assembly failures (e.g. "fixup value out of range").
    #
    # The bootstrap snapshot is primarily a stage0-free fallback; verifying the bytecode build
    # is sufficient to ensure the snapshot is structurally sound and runnable everywhere.
    dune build ./out.bc >/dev/null
  )
  rm -rf "$BOOTSTRAP_VERIFY_DIR"
  verify_end_ts="$(date +%s)"
  echo "== Bootstrap verification duration: $((verify_end_ts - verify_start_ts))s"
else
  echo "== Skipping bootstrap snapshot verify (HXHX_BOOTSTRAP_VERIFY=0)"
fi

echo "OK: regenerated bootstrap snapshot"
