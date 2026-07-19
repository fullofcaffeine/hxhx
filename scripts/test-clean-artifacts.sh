#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEAN_SCRIPT="$ROOT/scripts/dev/clean-artifacts.sh"
OUT_DIR="$ROOT/test/portable/fixtures/ereg_matchsub_optional_len/out"
PLACEHOLDER="$OUT_DIR/.gitignore"
TEMP_FILE="$OUT_DIR/.clean-artifacts-regression.tmp"
TEMP_SUBDIR="$OUT_DIR/.clean-artifacts-regression-dir"
TEMP_SUBFILE="$TEMP_SUBDIR/tmp.txt"
PACKAGE_TEST_OUT="$ROOT/test/packaging/reflaxe_ocaml_external_app/out"
PACKAGE_TEST_FILE="$PACKAGE_TEST_OUT/.clean-artifacts-regression.tmp"
BOOTSTRAP_INACTIVE_DIR="$ROOT/.tmp/hxhx-bootstrap-build.clean-regression-inactive"
BOOTSTRAP_ACTIVE_DIR="$ROOT/.tmp/hxhx-bootstrap-build.clean-regression-active"
BOOTSTRAP_PID_FILE=".hxhx-bootstrap-build.pid"
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
  rm -rf "$PACKAGE_TEST_OUT"
  rm -rf "$BOOTSTRAP_INACTIVE_DIR"
  rm -rf "$BOOTSTRAP_ACTIVE_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_SUBDIR"
printf 'temp\n' >"$TEMP_FILE"
printf 'temp\n' >"$TEMP_SUBFILE"
mkdir -p "$PACKAGE_TEST_OUT"
printf 'temp\n' >"$PACKAGE_TEST_FILE"

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
if [[ -e "$PACKAGE_TEST_OUT" ]]; then
  echo "Cleanup failed to remove an untracked packaging-test output directory." >&2
  exit 1
fi

mkdir -p "$BOOTSTRAP_INACTIVE_DIR" "$BOOTSTRAP_ACTIVE_DIR"
printf 'stale\n' >"$BOOTSTRAP_INACTIVE_DIR/artifact.txt"
printf 'active\n' >"$BOOTSTRAP_ACTIVE_DIR/artifact.txt"
printf '%s\n' "$$" >"$BOOTSTRAP_ACTIVE_DIR/$BOOTSTRAP_PID_FILE"

deep_preview="$(bash "$CLEAN_SCRIPT" --deep --yes --dry-run --verbose)"
if [[ "$deep_preview" != *"$BOOTSTRAP_INACTIVE_DIR"* ]]; then
  echo "Deep cleanup dry-run did not report inactive bootstrap build dir." >&2
  exit 1
fi
if [[ "$deep_preview" == *"$BOOTSTRAP_ACTIVE_DIR"* ]]; then
  echo "Deep cleanup dry-run reported active bootstrap build dir." >&2
  exit 1
fi

bash "$CLEAN_SCRIPT" --deep --yes >/dev/null

if [[ -e "$BOOTSTRAP_INACTIVE_DIR" ]]; then
  echo "Deep cleanup failed to remove inactive bootstrap build dir." >&2
  exit 1
fi
if [[ ! -d "$BOOTSTRAP_ACTIVE_DIR" ]]; then
  echo "Deep cleanup removed active bootstrap build dir." >&2
  exit 1
fi

echo "✓ Clean artifacts regression OK"
