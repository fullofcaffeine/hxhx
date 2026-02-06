#!/usr/bin/env bash
set -euo pipefail

# Gate 1 entrypoint (current default: native/non-delegating attempt).
#
# This script is what `npm run test:upstream:unit-macro` calls.
#
# If you want the historical stage0-shim behavior (delegating compilation to the system `haxe` binary),
# run:
#   bash scripts/hxhx/run-upstream-unit-macro-stage0.sh
#
# Rationale
# - We want “Gate 1” to converge on a non-delegating `hxhx` over time.
# - Keeping the stage0 shim as a separate script preserves a stable baseline for harness debugging.

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-upstream-unit-macro-native.sh"
