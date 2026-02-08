#!/usr/bin/env bash
set -euo pipefail

# Gate 2 entrypoint (default: non-delegating Stage3 no-emit, direct Macro sequence).
#
# This script is what `npm run test:upstream:runci-macro` calls.
#
# If you want the historical stage0-harness behavior (RunCi executed by stage0 `haxe`,
# with sub-invocations wrapped through `hxhx`), run:
#   npm run test:upstream:runci-macro-stage0
#
# Rationale
# - Gate2 acceptance wants a non-delegating `hxhx` in the hot path.
# - The stage3_no_emit pipeline is already valuable as a semantic/typer/macro oracle for the Macro
#   target workload, but executing upstream RunCi itself under the Stage3 bootstrap emitter is still
#   a long-term bring-up effort.
# - So the default Gate2 runner is now the stage0-free direct Macro sequence:
#     unit → display → sourcemaps → nullsafety → misc → threads (+ sys/party conditionals),
#   with every `haxe` call routed through `hxhx --hxhx-stage3 --hxhx-no-emit`.
#
# If you want the experimental "native attempt" (compile+run upstream `tests/RunCi.hxml` under the
# Stage3 bootstrap emitter), set:
#   HXHX_GATE2_MODE=stage3_emit_runner
#
# If you want the bring-up minimal harness (patches `tests/RunCi.hx` in the temporary worktree to
# prove sub-invocation spawning), set:
#   HXHX_GATE2_MODE=stage3_emit_runner_minimal

export HXHX_GATE2_MODE="${HXHX_GATE2_MODE:-stage3_no_emit_direct}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-upstream-runci-macro.sh"
