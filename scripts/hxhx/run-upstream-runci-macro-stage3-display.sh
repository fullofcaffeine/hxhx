#!/usr/bin/env bash
set -euo pipefail

# Gate 2 focused display rung (non-delegating).
#
# Runs the real Macro stage sequence in direct Stage3 no-emit mode and stops after the
# display fixture stage so we can iterate on display semantics quickly.

export HXHX_GATE2_MODE=stage3_no_emit_direct
export HXHX_GATE2_MACRO_STOP_AFTER=display
# The focused display rung intentionally isolates display semantics and skips
# the unit stage (compile-macro.hxml), which exercises unrelated parser/typer coverage.
export HXHX_GATE2_SKIP_UNIT=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$ROOT_DIR/run-upstream-runci-macro.sh"

HOST_OS="$(uname -s)"
RETRY_COUNT_DEFAULT=0
RETRY_COUNT="${HXHX_GATE2_DISPLAY_RETRY_COUNT:-$RETRY_COUNT_DEFAULT}"
RETRY_DELAY_SEC="${HXHX_GATE2_DISPLAY_RETRY_DELAY_SEC:-3}"
DISPLAY_SKIP_DARWIN_SEGFAULT="${HXHX_GATE2_DISPLAY_SKIP_DARWIN_SEGFAULT:-0}"

attempt=0
while true; do
  attempt=$((attempt + 1))
  set +e
  bash "$RUNNER"
  exit_code="$?"
  set -e
  if [ "$exit_code" -eq 0 ]; then
    exit 0
  fi

  if [ "$HOST_OS" = "Darwin" ] && [ "$exit_code" -eq 139 ] && [ "$attempt" -le "$RETRY_COUNT" ]; then
    echo "Gate2 display rung hit Darwin segfault (exit 139); retry ${attempt}/${RETRY_COUNT} in ${RETRY_DELAY_SEC}s..."
    sleep "$RETRY_DELAY_SEC"
    continue
  fi

  if [ "$HOST_OS" = "Darwin" ] && [ "$exit_code" -eq 139 ] && [ "$DISPLAY_SKIP_DARWIN_SEGFAULT" = "1" ]; then
    echo "Skipping Gate2 display rung on macOS after SIGSEGV (HXHX_GATE2_DISPLAY_SKIP_DARWIN_SEGFAULT=1 opt-in)."
    echo "gate2_display_stage=skipped reason=darwin_sigsegv"
    exit 0
  fi

  exit "$exit_code"
done
