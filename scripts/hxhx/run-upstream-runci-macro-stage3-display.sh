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

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-upstream-runci-macro.sh"
