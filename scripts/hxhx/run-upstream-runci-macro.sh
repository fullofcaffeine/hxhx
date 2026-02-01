#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

UPSTREAM_DIR_ORIG="$UPSTREAM_DIR"
UPSTREAM_WORKTREE_DIR=""
WRAP_DIR=""
ISO_DIR=""

cleanup() {
  if [ -n "$WRAP_DIR" ] && [ -d "$WRAP_DIR" ]; then
    rm -rf "$WRAP_DIR" >/dev/null 2>&1 || true
  fi

  if [ -n "$UPSTREAM_WORKTREE_DIR" ] && [ -d "$UPSTREAM_WORKTREE_DIR" ]; then
    git -C "$UPSTREAM_DIR_ORIG" worktree remove --force "$UPSTREAM_WORKTREE_DIR" >/dev/null 2>&1 || true
    rm -rf "$UPSTREAM_WORKTREE_DIR" >/dev/null 2>&1 || true
  fi

  if [ -n "$ISO_DIR" ] && [ -d "$ISO_DIR" ]; then
    rm -rf "$ISO_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ ! -d "$UPSTREAM_DIR/tests/runci" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 2: missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
  exit 1
fi

if ! command -v nekotools >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2: nekotools not found on PATH (RunCi uses it for the echo server)." >&2
  exit 0
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2: dune/ocamlc not found on PATH."
  exit 0
fi

# Resolve stage0 tool paths once so later wrapper scripts don't depend on PATH ordering.
STAGE0_HAXE="$(command -v "$HAXE_BIN")"
STAGE0_HAXELIB="$(command -v "$HAXELIB_BIN")"

# We want the upstream tests to match our compatibility target (default: 4.3.7).
# Instead of mutating the user's checkout, we run from a temporary git worktree when possible.
if command -v git >/dev/null 2>&1 && git -C "$UPSTREAM_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  UPSTREAM_WORKTREE_DIR="$(mktemp -d)"

  # If the ref doesn't exist locally, fall back to the current checkout.
  if git -C "$UPSTREAM_DIR_ORIG" rev-parse --verify --quiet "$UPSTREAM_REF^{commit}" >/dev/null 2>&1; then
    git -C "$UPSTREAM_DIR_ORIG" worktree add --detach "$UPSTREAM_WORKTREE_DIR" "$UPSTREAM_REF" >/dev/null
    UPSTREAM_DIR="$UPSTREAM_WORKTREE_DIR"
  fi
else
  echo "Skipping upstream Gate 2: HAXE_UPSTREAM_DIR is not a git checkout (worktree is required to avoid modifying your upstream repo)." >&2
  exit 0
fi

# Upstream `tests/misc` includes many per-issue project folders that reference `-cp src`.
# Git doesn't track empty directories, so in some checkouts those `src/` dirs are missing,
# which causes the misc harness to fail early with "classpath src is not a directory".
# Creating the empty directories is harmless and matches the intent of those fixtures.
ensure_misc_src_dirs() {
  local projects="$UPSTREAM_DIR/tests/misc/projects"
  [ -d "$projects" ] || return 0

  local files=""
  if command -v rg >/dev/null 2>&1; then
    files="$(rg -l '^-cp src$' "$projects" --glob '*.hxml' --no-messages || true)"
  else
    files="$(grep -R -l '^-cp src$' "$projects" --include '*.hxml' 2>/dev/null || true)"
  fi

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    mkdir -p "$(dirname "$f")/src"
  done <<<"$files"
}

# Some upstream/fork checkouts contain quoted args inside `.hxml` fixtures like:
#   --display "Main.hx@0@diagnostics"
#   -cp "dir with spaces"
# Haxe's `.hxml` parser treats those quotes as literal characters (it does not shell-parse),
# which can break the tests. Because we're running from a temporary worktree, we can safely
# normalize these fixtures in-place without mutating the user's checkout.
normalize_quoted_hxml_args() {
  local projects="$UPSTREAM_DIR/tests/misc/projects"
  [ -d "$projects" ] || return 0

  local files=""
  if command -v rg >/dev/null 2>&1; then
    files="$(rg -l "^-\\S+\\s+['\\\"]" "$projects" --glob '*.hxml' --no-messages || true)"
  else
    files="$(grep -R -l -E "^-\\S+[[:space:]]+['\\\"]" "$projects" --include '*.hxml' 2>/dev/null || true)"
  fi

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local tmp
    tmp="$(mktemp)"
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" =~ ^(-[^[:space:]]+)[[:space:]]+\"(.*)\"$ ]]; then
        line="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      elif [[ "$line" =~ ^(-[^[:space:]]+)[[:space:]]+\'(.*)\'$ ]]; then
        line="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      fi
      printf '%s\n' "$line"
    done <"$f" >"$tmp"
    mv "$tmp" "$f"
  done <<<"$files"
}

# Isolate haxelib/haxe state so RunCi doesn't mutate the user's global setup (~/.haxelib).
ISO_DIR="$(mktemp -d)"
ISO_HOME="$ISO_DIR/home"
ISO_HAXELIB_REPO="$ISO_DIR/haxelib"
mkdir -p "$ISO_HOME" "$ISO_HAXELIB_REPO"
printf '%s\n' "$ISO_HAXELIB_REPO" >"$ISO_HOME/.haxelib"

# runci Macro relies on a working `haxe` command. To run it through `hxhx`,
# we prepend a wrapper called `haxe` to PATH and point `hxhx` at the real stage0
# compiler via HAXE_BIN to avoid recursion.
HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

WRAP_DIR="$(mktemp -d)"

cat >"$WRAP_DIR/haxe" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export HAXE_BIN="${STAGE0_HAXE}"
exec "${HXHX_BIN}" "\$@"
EOF
chmod +x "$WRAP_DIR/haxe"

cat >"$WRAP_DIR/haxelib" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "${STAGE0_HAXELIB}" "\$@"
EOF
chmod +x "$WRAP_DIR/haxelib"

echo "== Gate 2: upstream tests/runci Macro target (via hxhx stage0 shim)"
(
  cd "$UPSTREAM_DIR/tests"
  ensure_misc_src_dirs
  normalize_quoted_hxml_args
  # RunCi defaults to the Macro target when no args/TEST are provided.
  # We intentionally pass no args here because `hxhx` treats `--` as a separator
  # and would drop everything before it.
  HOME="$ISO_HOME" PATH="$WRAP_DIR:$PATH" "$STAGE0_HAXE" RunCi.hxml
)
