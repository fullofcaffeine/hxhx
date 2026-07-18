#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$ROOT/.tmp/current-source-cache-fixture.$$"
repo="$fixture/repo"
fake_bin="$fixture/bin/hxhx"
meta="$fixture/hxhx-current-source.env"
validate="$ROOT/scripts/hxhx/validate-current-source-hxhx-bin.sh"

cleanup() {
  rm -rf "$fixture" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hash_stream() {
  shasum -a 256 | awk '{print $1}'
}

tracked_status() {
  git -C "$repo" status --porcelain --untracked-files=no
}

tracked_tree() {
  git -C "$repo" diff --no-ext-diff --binary HEAD -- .
}

status_hash() {
  tracked_status | hash_stream
}

tree_hash() {
  tracked_tree | hash_stream
}

write_meta() {
  local head
  local status
  local status_sha
  local tree_sha
  local dirty

  head="$(git -C "$repo" rev-parse HEAD)"
  status="$(tracked_status)"
  status_sha="$(printf '%s' "$status" | hash_stream)"
  tree_sha="$(tree_hash)"
  dirty=0
  if [ -n "$status" ]; then
    dirty=1
  fi

  cat >"$meta" <<META
# fixture metadata
HXHX_BIN=$fake_bin
HXHX_BIN_PROVENANCE=current-source-stage0
HXHX_BIN_BUILD_PROFILE=full
HXHX_BIN_SOURCE_HEAD=$head
HXHX_BIN_SOURCE_BRANCH=main
HXHX_BIN_SOURCE_DIRTY=$dirty
HXHX_BIN_SOURCE_STATUS_SHA256=$status_sha
HXHX_BIN_SOURCE_TREE_SHA256=$tree_sha
HXHX_BIN_BUILT_AT_EPOCH=1
HXHX_BIN_BUILD_SECONDS=0
META
}

validate_ok() {
  local out
  out="$(HXHX_CURRENT_SOURCE_ROOT="$repo" HXHX_CURRENT_SOURCE_META="$meta" bash "$validate" "$fake_bin")"
  if [ "$out" != "$fake_bin" ]; then
    echo "expected validate output to be fake binary path, got: $out" >&2
    exit 1
  fi
}

rm -rf "$fixture"
mkdir -p "$repo" "$(dirname "$fake_bin")"

git -C "$repo" init -q
git -C "$repo" config user.email current-source-cache@example.invalid
git -C "$repo" config user.name "Current Source Cache Fixture"

printf 'clean\n' >"$repo/tracked.txt"
git -C "$repo" add tracked.txt
git -C "$repo" commit -q -m initial

printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_bin"
chmod +x "$fake_bin"

write_meta
validate_ok

printf 'dirty-a\n' >"$repo/tracked.txt"
write_meta
validate_ok

old_status_sha="$(status_hash)"
old_tree_sha="$(tree_hash)"
printf 'dirty-b\n' >"$repo/tracked.txt"
new_status_sha="$(status_hash)"
new_tree_sha="$(tree_hash)"

if [ "$old_status_sha" != "$new_status_sha" ]; then
  echo "fixture no longer preserves the same tracked status hash across content-only dirty edits" >&2
  exit 1
fi
if [ "$old_tree_sha" = "$new_tree_sha" ]; then
  echo "tracked content hash did not change after modifying dirty tracked content" >&2
  exit 1
fi

failure_log="$fixture/validate-failure.log"
if HXHX_CURRENT_SOURCE_ROOT="$repo" HXHX_CURRENT_SOURCE_META="$meta" bash "$validate" "$fake_bin" >"$fixture/unexpected.out" 2>"$failure_log"; then
  echo "validation unexpectedly accepted stale dirty tracked content" >&2
  exit 1
fi
grep -Fq "tracked worktree content changed since build" "$failure_log"

stale_log="$fixture/validate-stale.log"
out="$(HXHX_CURRENT_SOURCE_ROOT="$repo" HXHX_CURRENT_SOURCE_META="$meta" HXHX_CURRENT_SOURCE_ALLOW_STALE=1 bash "$validate" "$fake_bin" 2>"$stale_log")"
if [ "$out" != "$fake_bin" ]; then
  echo "stale diagnostic reuse should still return the fake binary path" >&2
  exit 1
fi
grep -Fq "warning: tracked worktree content changed since build" "$stale_log"

write_meta
validate_ok

grep -v '^HXHX_BIN_SOURCE_TREE_SHA256=' "$meta" >"$fixture/legacy.env"
mv "$fixture/legacy.env" "$meta"
if HXHX_CURRENT_SOURCE_ROOT="$repo" HXHX_CURRENT_SOURCE_META="$meta" bash "$validate" "$fake_bin" >"$fixture/legacy.out" 2>"$fixture/legacy.err"; then
  echo "validation unexpectedly accepted legacy metadata without tracked content hash" >&2
  exit 1
fi
grep -Fq "missing tracked worktree content hash" "$fixture/legacy.err"

echo "current-source cache fixture OK"
