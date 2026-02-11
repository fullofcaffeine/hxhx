#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [ ! -f "haxelib.json" ]; then
  echo "Missing haxelib.json at repo root." >&2
  exit 1
fi

VERSION="$(node -pe 'require("./haxelib.json").version')"
if [ -z "$VERSION" ]; then
  echo "Failed to read version from haxelib.json" >&2
  exit 1
fi

OUT_DIR="$ROOT/dist"
mkdir -p "$OUT_DIR"

ZIP_PATH="$OUT_DIR/reflaxe.ocaml-$VERSION.zip"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

mkdir -p "$TMP_DIR/reflaxe.ocaml"

# Minimal Haxelib payload:
# - compiler source (`packages/reflaxe.ocaml/src/`)
# - stdlib surfaces + runtime (`packages/reflaxe.ocaml/std/`)
# - metadata files + docs
mkdir -p "$TMP_DIR/reflaxe.ocaml/packages/reflaxe.ocaml"
cp -R "packages/reflaxe.ocaml/src" "$TMP_DIR/reflaxe.ocaml/packages/reflaxe.ocaml/"
cp -R "packages/reflaxe.ocaml/std" "$TMP_DIR/reflaxe.ocaml/packages/reflaxe.ocaml/"
cp "haxelib.json" "$TMP_DIR/reflaxe.ocaml/"
cp "README.md" "$TMP_DIR/reflaxe.ocaml/"
cp "LICENSE" "$TMP_DIR/reflaxe.ocaml/"
cp "CHANGELOG.md" "$TMP_DIR/reflaxe.ocaml/"

# Optional: include the local dev hxml so users can inspect the pinned setup.
if [ -f "haxe_libraries/reflaxe.ocaml.hxml" ]; then
  mkdir -p "$TMP_DIR/reflaxe.ocaml/haxe_libraries"
  cp "haxe_libraries/reflaxe.ocaml.hxml" "$TMP_DIR/reflaxe.ocaml/haxe_libraries/"
fi

(cd "$TMP_DIR" && zip -qr "$ZIP_PATH" "reflaxe.ocaml")

echo "Wrote: $ZIP_PATH"
