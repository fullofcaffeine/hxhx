#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

# Stable npm/CI entrypoint for Haxe formatting.
#
# Beginner-friendly map:
# - This shell script does not format files itself.
# - It moves to the repo root and runs the Node guard below.
# - The Node guard delegates to the official `haxelib run formatter --check`.
# - The Node guard only makes the check faster by isolating oversized files,
#   line-balancing the rest, and feeding those deterministic tasks to a bounded
#   worker queue.
#
# HX_FORMAT_JOBS controls the concurrent process limit; default "auto" caps at four jobs.
# Oversized files use at most two lanes while ordinary chunks remain parallel.
# HX_FORMAT_OVERSIZED_JOBS can lower the heavy-task cap on a constrained host.
# HX_FORMAT_TIMEOUT_SECONDS bounds one formatter task; the default is four minutes.
exec node scripts/lint/hx-format-guard.js
