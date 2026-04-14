#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

UPSTREAM_REMOTE="${REFLAXE_ELIXIR_REMOTE:-https://github.com/fullofcaffeine/reflaxe.elixir.git}"
DEFAULT_REFLAXE_ELIXIR_REF="5b322236e0627f8322394e819cf28ba6c1271a83"
UPSTREAM_REF="${REFLAXE_ELIXIR_REF:-$DEFAULT_REFLAXE_ELIXIR_REF}"
DEST_DIR="${REFLAXE_ELIXIR_DIR:-$ROOT/vendor/reflaxe-elixir}"
TODO_SRC_REL="examples/todo-app/src_haxe"

if [[ ! "$UPSTREAM_REF" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "fetch-reflaxe-elixir-upstream: REFLAXE_ELIXIR_REF must be a pinned 40-character commit SHA, got: $UPSTREAM_REF" >&2
  echo "fetch-reflaxe-elixir-upstream: branch, tag, and symbolic refs are intentionally rejected for deterministic pilot evidence" >&2
  exit 2
fi

mkdir -p "$(dirname "$DEST_DIR")"

if [ -d "$DEST_DIR/.git" ]; then
  echo "Updating reflaxe.elixir checkout: $DEST_DIR"
  if git -C "$DEST_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$DEST_DIR" remote set-url origin "$UPSTREAM_REMOTE"
  else
    git -C "$DEST_DIR" remote add origin "$UPSTREAM_REMOTE"
  fi
else
  echo "Cloning reflaxe.elixir checkout to: $DEST_DIR"
  git clone --filter=blob:none --no-checkout "$UPSTREAM_REMOTE" "$DEST_DIR" >/dev/null
fi

echo "Checking out reflaxe.elixir pinned commit: $UPSTREAM_REF"
git -C "$DEST_DIR" fetch --depth 1 origin "$UPSTREAM_REF" >/dev/null
git -C "$DEST_DIR" checkout --detach FETCH_HEAD >/dev/null

TODO_SRC="$DEST_DIR/$TODO_SRC_REL"
if [ ! -d "$TODO_SRC" ]; then
  echo "fetch-reflaxe-elixir-upstream: missing todo source directory at $TODO_SRC" >&2
  exit 2
fi

RESOLVED_COMMIT="$(git -C "$DEST_DIR" rev-parse HEAD)"
if [ "$RESOLVED_COMMIT" != "$UPSTREAM_REF" ]; then
  echo "fetch-reflaxe-elixir-upstream: resolved commit mismatch: requested=$UPSTREAM_REF actual=$RESOLVED_COMMIT" >&2
  exit 2
fi

echo "reflaxe_elixir_dir=$DEST_DIR"
echo "reflaxe_elixir_ref=$UPSTREAM_REF"
echo "reflaxe_elixir_commit=$RESOLVED_COMMIT"
echo "reflaxe_elixir_todo_src=$TODO_SRC"
echo "REFLAXE_ELIXIR_PINNED:PASS"
