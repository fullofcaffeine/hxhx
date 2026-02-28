#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

UPSTREAM_REMOTE="${REFLAXE_ELIXIR_REMOTE:-https://github.com/fullofcaffeine/reflaxe.elixir.git}"
UPSTREAM_REF="${REFLAXE_ELIXIR_REF:-main}"
DEST_DIR="${REFLAXE_ELIXIR_DIR:-$ROOT/vendor/reflaxe-elixir}"
TODO_SRC_REL="examples/todo-app/src_haxe"

mkdir -p "$(dirname "$DEST_DIR")"

if [ -d "$DEST_DIR/.git" ]; then
  echo "Updating reflaxe.elixir checkout: $DEST_DIR"
  git -C "$DEST_DIR" fetch --tags --prune >/dev/null
else
  echo "Cloning reflaxe.elixir checkout to: $DEST_DIR"
  git clone --filter=blob:none --tags "$UPSTREAM_REMOTE" "$DEST_DIR" >/dev/null
fi

echo "Checking out reflaxe.elixir ref: $UPSTREAM_REF"
git -C "$DEST_DIR" checkout --detach "$UPSTREAM_REF" >/dev/null

TODO_SRC="$DEST_DIR/$TODO_SRC_REL"
if [ ! -d "$TODO_SRC" ]; then
  echo "fetch-reflaxe-elixir-upstream: missing todo source directory at $TODO_SRC" >&2
  exit 2
fi

RESOLVED_COMMIT="$(git -C "$DEST_DIR" rev-parse HEAD)"

echo "reflaxe_elixir_dir=$DEST_DIR"
echo "reflaxe_elixir_ref=$UPSTREAM_REF"
echo "reflaxe_elixir_commit=$RESOLVED_COMMIT"
echo "reflaxe_elixir_todo_src=$TODO_SRC"
