#!/usr/bin/env bash
set -euo pipefail

# Gate 2 entrypoint (current default: native/non-delegating attempt).
#
# This script is what `npm run test:upstream:runci-macro` calls.
#
# If you want the historical stage0-harness behavior (RunCi executed by stage0 `haxe`,
# with sub-invocations wrapped through `hxhx`), run:
#   npm run test:upstream:runci-macro-stage0
#
# Rationale
# - Like Gate1, we want the default Gate2 runner to converge on a non-delegating `hxhx`.
# - Today "native Gate2" is still a bring-up rung: we compile+run the upstream `tests/RunCi.hxml`
#   using `hxhx --hxhx-stage3 --hxhx-emit-full-bodies`, while routing `haxe` sub-invocations through
#   `hxhx --hxhx-stage3 --hxhx-no-emit` to surface frontend/typer/macro gaps early.

export HXHX_GATE2_MODE="${HXHX_GATE2_MODE:-stage3_emit_runner}"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-upstream-runci-macro.sh"

