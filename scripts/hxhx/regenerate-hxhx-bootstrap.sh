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
HXHX_STAGE0_HEARTBEAT="${HXHX_STAGE0_HEARTBEAT:-0}"
HXHX_STAGE0_LOG_TAIL_LINES="${HXHX_STAGE0_LOG_TAIL_LINES:-80}"
HXHX_STAGE0_FAILFAST_SECS="${HXHX_STAGE0_FAILFAST_SECS:-900}"
HXHX_STAGE0_HEARTBEAT_TAIL_LINES="${HXHX_STAGE0_HEARTBEAT_TAIL_LINES:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKG_DIR="$ROOT/packages/hxhx"
OUT_DIR="$PKG_DIR/out"
BOOTSTRAP_DIR="$PKG_DIR/bootstrap_out"

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

    log_file="$(mktemp -t hxhx-stage0-emit.XXXXXX.log)"
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
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid child=$child_pid"
        else
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s rss=${rss_mb}MB pid=$pid"
        fi
      else
        if [ -n "$child_pid" ]; then
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s pid=$pid child=$child_pid"
        else
          echo "== Stage0 emit heartbeat: elapsed=$((now - start_hb))s pid=$pid"
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
      exit "$code"
    fi

    if [ "$HXHX_BOOTSTRAP_DEBUG" = "1" ]; then
      echo "== Stage0 emit completed; last $HXHX_STAGE0_LOG_TAIL_LINES lines:"
      tail -n "$HXHX_STAGE0_LOG_TAIL_LINES" "$log_file" || true
    fi
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
rm -rf "$BOOTSTRAP_DIR"
mkdir -p "$BOOTSTRAP_DIR"

# Copy everything except build artifacts and generator sources.
(cd "$OUT_DIR" && tar --exclude='_build' --exclude='_gen_hx' -cf - .) | (cd "$BOOTSTRAP_DIR" && tar -xf -)

echo "== Verifying bootstrap snapshot builds (dune)"
(
  cd "$BOOTSTRAP_DIR"
  # NOTE: On some platforms (notably macOS/arm64), extremely large generated compilation units
  # can cause native `ocamlopt` assembly failures (e.g. "fixup value out of range").
  #
  # The bootstrap snapshot is primarily a stage0-free fallback; verifying the bytecode build
  # is sufficient to ensure the snapshot is structurally sound and runnable everywhere.
  dune build ./out.bc >/dev/null
)

echo "OK: regenerated bootstrap snapshot"
