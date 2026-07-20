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
MACRO_HOST_INACTIVE_DIR="$ROOT/.tmp/hxhx-macro-host-build.clean-regression-inactive"
MACRO_HOST_ACTIVE_DIR="$ROOT/.tmp/hxhx-macro-host-build.clean-regression-active"
MACRO_HOST_PENDING_DIR="$ROOT/.tmp/hxhx-macro-host-build.clean-regression-pending"
MACRO_HOST_PID_SUFFIX=".hxhx-macro-host-build.pid"
MACRO_HOST_GENERATED_INPUT_SUFFIX=".hxhx-macro-host-input"
MACRO_HOST_INACTIVE_PID_FILE="${MACRO_HOST_INACTIVE_DIR}${MACRO_HOST_PID_SUFFIX}"
MACRO_HOST_ACTIVE_PID_FILE="${MACRO_HOST_ACTIVE_DIR}${MACRO_HOST_PID_SUFFIX}"
MACRO_HOST_PENDING_PID_FILE="${MACRO_HOST_PENDING_DIR}${MACRO_HOST_PID_SUFFIX}"
MACRO_HOST_INACTIVE_INPUT_DIR="${MACRO_HOST_INACTIVE_DIR}${MACRO_HOST_GENERATED_INPUT_SUFFIX}"
MACRO_HOST_ACTIVE_INPUT_DIR="${MACRO_HOST_ACTIVE_DIR}${MACRO_HOST_GENERATED_INPUT_SUFFIX}"
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
  rm -rf "$MACRO_HOST_INACTIVE_DIR"
  rm -rf "$MACRO_HOST_ACTIVE_DIR"
  rm -rf "$MACRO_HOST_PENDING_DIR"
  rm -f "$MACRO_HOST_INACTIVE_PID_FILE"
  rm -f "$MACRO_HOST_ACTIVE_PID_FILE"
  rm -f "$MACRO_HOST_PENDING_PID_FILE"
  rm -rf "$MACRO_HOST_INACTIVE_INPUT_DIR"
  rm -rf "$MACRO_HOST_ACTIVE_INPUT_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_SUBDIR"
printf 'temp\n' >"$TEMP_FILE"
printf 'temp\n' >"$TEMP_SUBFILE"
mkdir -p "$PACKAGE_TEST_OUT"
printf 'temp\n' >"$PACKAGE_TEST_FILE"

mkdir -p "$MACRO_HOST_INACTIVE_DIR" "$MACRO_HOST_ACTIVE_DIR"
printf 'stale\n' >"$MACRO_HOST_INACTIVE_DIR/artifact.txt"
printf 'active\n' >"$MACRO_HOST_ACTIVE_DIR/artifact.txt"
printf '%s\n' "99999999" >"$MACRO_HOST_INACTIVE_PID_FILE"
printf '%s\n' "$$" >"$MACRO_HOST_ACTIVE_PID_FILE"
mkdir -p "$MACRO_HOST_INACTIVE_INPUT_DIR" "$MACRO_HOST_ACTIVE_INPUT_DIR"
printf 'stale input\n' >"$MACRO_HOST_INACTIVE_INPUT_DIR/EntryPointsGen.hx"
printf 'active input\n' >"$MACRO_HOST_ACTIVE_INPUT_DIR/EntryPointsGen.hx"
# A builder writes its lease before recreating the output directory. Cleanup
# must respect that short interval instead of deleting the lease as orphaned.
printf '%s\n' "$$" >"$MACRO_HOST_PENDING_PID_FILE"

safe_preview="$(bash "$CLEAN_SCRIPT" --safe --dry-run --verbose)"
if [[ "$safe_preview" != *"$MACRO_HOST_INACTIVE_DIR"* ]]; then
  echo "Safe cleanup dry-run did not report inactive macro-host build dir." >&2
  exit 1
fi
if [[ "$safe_preview" == *"$MACRO_HOST_ACTIVE_DIR"* ]]; then
  echo "Safe cleanup dry-run reported active macro-host build dir." >&2
  exit 1
fi
if [[ "$safe_preview" == *"$MACRO_HOST_PENDING_PID_FILE"* ]]; then
  echo "Safe cleanup dry-run reported a live macro-host lease before its build directory existed." >&2
  exit 1
fi

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
if [[ -e "$MACRO_HOST_INACTIVE_DIR" ]]; then
  echo "Safe cleanup failed to remove inactive macro-host build dir." >&2
  exit 1
fi
if [[ -e "$MACRO_HOST_INACTIVE_PID_FILE" ]]; then
  echo "Safe cleanup failed to remove an inactive macro-host build lease." >&2
  exit 1
fi
if [[ -e "$MACRO_HOST_INACTIVE_INPUT_DIR" ]]; then
  echo "Safe cleanup failed to remove inactive macro-host generated inputs." >&2
  exit 1
fi
if [[ ! -d "$MACRO_HOST_ACTIVE_DIR" ]]; then
  echo "Safe cleanup removed active macro-host build dir." >&2
  exit 1
fi
if [[ ! -f "$MACRO_HOST_ACTIVE_PID_FILE" ]]; then
  echo "Safe cleanup removed an active macro-host build lease." >&2
  exit 1
fi
if [[ ! -d "$MACRO_HOST_ACTIVE_INPUT_DIR" ]]; then
  echo "Safe cleanup removed active macro-host generated inputs." >&2
  exit 1
fi
if [[ ! -f "$MACRO_HOST_PENDING_PID_FILE" ]]; then
  echo "Safe cleanup removed a live macro-host lease before its build directory existed." >&2
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
