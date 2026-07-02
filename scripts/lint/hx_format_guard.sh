#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

# Stable npm/CI entrypoint for Haxe formatting. The Node helper still delegates
# to haxelib formatter; it only parallelizes line-balanced --check chunks.
# HX_FORMAT_JOBS controls chunk count; default "auto" caps at four jobs.
exec node scripts/lint/hx-format-guard.js
