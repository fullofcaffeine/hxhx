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
start_ts="$(date +%s)"
(
  # We only need the emitted OCaml sources for the snapshot. Running the full OCaml build step
  # (dune/ocamlopt) here is redundant, and it can make snapshot refreshes significantly slower.
  #
  # `-D ocaml_emit_only` keeps stage0 as a codegen oracle while preserving the "stage0-free build"
  # property for everyone else via the committed snapshot + dune build in CI.
  cd "$PKG_DIR"
  rm -rf out
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
    if [ -z "${HXHX_STAGE0_HEARTBEAT}" ] || [ "$HXHX_STAGE0_HEARTBEAT" = "0" ]; then
      if [ "$HXHX_BOOTSTRAP_DEBUG" = "1" ]; then
        echo "== Stage0 emit command: $HAXE_BIN ${haxe_args[*]}"
        "$HAXE_BIN" "${haxe_args[@]}"
      else
        "$HAXE_BIN" "${haxe_args[@]}" >/dev/null
      fi
      return
    fi

    log_file="$(create_stage0_log_file hxhx-stage0-emit)"
    echo "== Stage0 emit command: $HAXE_BIN ${haxe_args[*]}"
    echo "== Stage0 emit log: $log_file"
    pid=""
    "$HAXE_BIN" "${haxe_args[@]}" >"$log_file" 2>&1 &
    pid="$!"

    # Heartbeat: keep maintainers confident it's making progress.
    interval="$HXHX_STAGE0_HEARTBEAT"
    start_hb="$(date +%s)"
    while kill -0 "$pid" >/dev/null 2>&1; do
      sleep "$interval" || true
      now="$(date +%s)"
      child_pid="$(pgrep -P "$pid" | head -n 1 || true)"
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
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid child=$child_pid$heartbeat_suffix"
        else
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid$heartbeat_suffix"
        fi
      else
        if [ -n "$child_pid" ]; then
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s pid=$pid child=$child_pid$heartbeat_suffix"
        else
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s pid=$pid$heartbeat_suffix"
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

echo "OK: regenerated bootstrap snapshot"
