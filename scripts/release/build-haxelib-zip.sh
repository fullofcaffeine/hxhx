#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PACKAGE_ROOT="$ROOT/packages/reflaxe.ocaml"

if [ ! -f "$PACKAGE_ROOT/haxelib.json" ]; then
  echo "Missing package haxelib.json at $PACKAGE_ROOT." >&2
  exit 1
fi

VERSION="$(node -pe 'require("./packages/reflaxe.ocaml/haxelib.json").version')"
if [ -z "$VERSION" ]; then
  echo "Failed to read version from packages/reflaxe.ocaml/haxelib.json" >&2
  exit 1
fi

ROOT_VERSION="$(node -pe 'require("./haxelib.json").version')"
if [ "$ROOT_VERSION" != "$VERSION" ]; then
  echo "Root haxelib.json version ($ROOT_VERSION) does not match package haxelib.json version ($VERSION)." >&2
  exit 1
fi

OUT_DIR="$ROOT/dist"
mkdir -p "$OUT_DIR"

ZIP_PATH="$OUT_DIR/reflaxe.ocaml-$VERSION.zip"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

WORK_DIR="$TMP_DIR/work/reflaxe.ocaml"
BUILD_DIR="$WORK_DIR/_Build"

mkdir -p "$WORK_DIR"
(cd "$PACKAGE_ROOT" && tar -cf - .) | (cd "$WORK_DIR" && tar -xf -)

cp "$ROOT/LICENSE" "$WORK_DIR/LICENSE"
cp "$ROOT/CHANGELOG.md" "$WORK_DIR/CHANGELOG.md"

REFLAXE_CP="$(haxelib path reflaxe 2>/dev/null | awk 'NF && $1 !~ /^-/ { print; exit }')"
if [ -z "$REFLAXE_CP" ]; then
  echo "Failed to resolve reflaxe with haxelib path." >&2
  exit 1
fi
REFLAXE_ROOT="${REFLAXE_CP%/}"
if [ "$(basename "$REFLAXE_ROOT")" = "src" ]; then
  REFLAXE_ROOT="$(dirname "$REFLAXE_ROOT")"
fi
if [ ! -f "$REFLAXE_ROOT/Run.hx" ]; then
  echo "Resolved reflaxe root does not contain Run.hx: $REFLAXE_ROOT" >&2
  exit 1
fi

(
  cd "$WORK_DIR"
  haxe -cp "$REFLAXE_ROOT" --run Run build _Build --deleteOldFolder "$WORK_DIR"
)

# Reflaxe copies LICENSE/README/extraParams/haxelib metadata into _Build.
# Keep this repo's changelog in the distributable package as release context.
cp "$WORK_DIR/CHANGELOG.md" "$BUILD_DIR/CHANGELOG.md"

(cd "$BUILD_DIR" && zip -qr "$ZIP_PATH" .)

echo "Wrote: $ZIP_PATH"
