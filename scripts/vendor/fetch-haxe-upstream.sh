#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

UPSTREAM_REMOTE="${HAXE_UPSTREAM_REMOTE:-https://github.com/HaxeFoundation/haxe.git}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"
DEST_DIR="${HAXE_UPSTREAM_DIR:-$ROOT/vendor/haxe}"

mkdir -p "$(dirname "$DEST_DIR")"

if [ -d "$DEST_DIR/.git" ]; then
  echo "Updating upstream Haxe checkout: $DEST_DIR"
  git -C "$DEST_DIR" fetch --tags --prune >/dev/null
else
  echo "Cloning upstream Haxe checkout to: $DEST_DIR"
  git clone --filter=blob:none --tags "$UPSTREAM_REMOTE" "$DEST_DIR" >/dev/null
fi

echo "Checking out upstream ref: $UPSTREAM_REF"
git -C "$DEST_DIR" checkout --detach "$UPSTREAM_REF" >/dev/null

echo "OK: upstream Haxe is ready at: $DEST_DIR"
