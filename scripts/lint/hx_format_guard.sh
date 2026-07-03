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
# - The Node guard only makes the check faster by splitting tracked `.hx` files
#   into deterministic, line-balanced chunks that can run in parallel.
#
# HX_FORMAT_JOBS controls the chunk count; default "auto" caps at four jobs.
exec node scripts/lint/hx-format-guard.js
