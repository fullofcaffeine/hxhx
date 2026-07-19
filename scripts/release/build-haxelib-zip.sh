#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage: bash scripts/release/build-haxelib-zip.sh [--out-dir <directory>]

Build a deterministic, source-only reflaxe.ocaml haxelib archive.
EOF
}

OUT_DIR="$ROOT/dist"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --out-dir)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --out-dir." >&2
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

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

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd -P)"

ZIP_PATH="$OUT_DIR/reflaxe.ocaml-$VERSION.zip"
TMP_BASE="${TMPDIR:-/tmp}"
mkdir -p "$TMP_BASE"
TMP_BASE="$(cd "$TMP_BASE" && pwd -P)"
TMP_DIR="$(mktemp -d "$TMP_BASE/reflaxe-ocaml-haxelib.XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

WORK_DIR="$TMP_DIR/work/reflaxe.ocaml"
BUILD_DIR="$WORK_DIR/_Build"

mkdir -p "$WORK_DIR"
node "$ROOT/scripts/release/prepare-haxelib-archive.js" stage \
  --package "packages/reflaxe.ocaml" \
  --out "$WORK_DIR"

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

# Reflaxe packages the Haxe classpath and std roots. Project scaffolds are
# package-owned data, so copy their tracked source tree into the source ZIP.
if [ ! -d "$WORK_DIR/templates" ]; then
  echo "Missing reflaxe.ocaml scaffold templates at $WORK_DIR/templates." >&2
  exit 1
fi
cp -R "$WORK_DIR/templates" "$BUILD_DIR/templates"

# Reflaxe copies LICENSE/README/extraParams/haxelib metadata into _Build.
# Keep this repo's changelog in the distributable package as release context.
cp "$WORK_DIR/CHANGELOG.md" "$BUILD_DIR/CHANGELOG.md"

ZIP_MANIFEST="$TMP_DIR/zip-files.txt"
node "$ROOT/scripts/release/prepare-haxelib-archive.js" finalize \
  --root "$BUILD_DIR" \
  --manifest "$ZIP_MANIFEST" \
  --epoch "${SOURCE_DATE_EPOCH:-315532800}"

rm -f "$ZIP_PATH"
(
  cd "$BUILD_DIR"
  export TZ=UTC
  zip -X -q "$ZIP_PATH" -@ < "$ZIP_MANIFEST"
)
zip -T "$ZIP_PATH" >/dev/null

echo "Wrote: $ZIP_PATH"
