#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEAN_SCRIPT="$ROOT/scripts/dev/clean-artifacts.sh"
OUT_DIR="$ROOT/test/portable/fixtures/ereg_matchsub_optional_len/out"
PLACEHOLDER="$OUT_DIR/.gitignore"
TEMP_FILE="$OUT_DIR/.clean-artifacts-regression.tmp"
TEMP_SUBDIR="$OUT_DIR/.clean-artifacts-regression-dir"
TEMP_SUBFILE="$TEMP_SUBDIR/tmp.txt"
PLACEHOLDER_REL="${PLACEHOLDER#"$ROOT/"}"

if [[ ! -f "$PLACEHOLDER" ]]; then
  echo "Missing placeholder file: $PLACEHOLDER" >&2
  exit 1
fi

if ! git -C "$ROOT" ls-files --error-unmatch -- "$PLACEHOLDER_REL" >/dev/null 2>&1; then
  echo "Expected tracked placeholder is not tracked: $PLACEHOLDER_REL" >&2
  exit 1
fi

cleanup() {
  rm -f "$TEMP_FILE"
  rm -rf "$TEMP_SUBDIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_SUBDIR"
printf 'temp\n' >"$TEMP_FILE"
printf 'temp\n' >"$TEMP_SUBFILE"

bash "$CLEAN_SCRIPT" --safe >/dev/null

if [[ ! -f "$PLACEHOLDER" ]]; then
  echo "Cleanup removed tracked placeholder: $PLACEHOLDER_REL" >&2
  exit 1
fi

if ! git -C "$ROOT" ls-files --error-unmatch -- "$PLACEHOLDER_REL" >/dev/null 2>&1; then
  echo "Tracked placeholder became untracked: $PLACEHOLDER_REL" >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT" status --short -- "$PLACEHOLDER_REL")" ]]; then
  echo "Cleanup modified tracked placeholder: $PLACEHOLDER_REL" >&2
  exit 1
fi

if [[ -e "$TEMP_FILE" || -e "$TEMP_SUBDIR" ]]; then
  echo "Cleanup failed to remove untracked artifacts from fixture out dir." >&2
  exit 1
fi

echo "✓ Clean artifacts regression OK"
