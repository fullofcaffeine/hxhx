#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping hxhx dist build: dune/ocamlc not found on PATH."
  exit 0
fi

if ! command -v tar >/dev/null 2>&1; then
  echo "Missing tar on PATH (required to package dist artifact)." >&2
  exit 1
fi

checksum_cmd=()
if command -v sha256sum >/dev/null 2>&1; then
  checksum_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  checksum_cmd=(shasum -a 256)
else
  echo "Missing sha256 tool on PATH (expected sha256sum or shasum)." >&2
  exit 1
fi

platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

version="${HXHX_VERSION:-}"
if [ -z "$version" ]; then
  if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    version="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || true)"
  fi
fi
if [ -z "$version" ]; then
  version="dev"
fi
version="${version#v}"

dist_root="$ROOT/dist/hxhx"
dist_dir="$dist_root/$version/$platform-$arch"
bin_dir="$dist_dir/bin"

rm -rf "$dist_dir"
mkdir -p "$bin_dir"

echo "== Building hxhx stage1 binary"
HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Missing built executable from build-hxhx.sh (expected a path to an .exe)." >&2
  exit 1
fi

cp "$HXHX_BIN" "$bin_dir/hxhx"
chmod +x "$bin_dir/hxhx"

cp "$ROOT/README.md" "$dist_dir/README.md"
cp "$ROOT/LICENSE" "$dist_dir/LICENSE"
cp "$ROOT/CHANGELOG.md" "$dist_dir/CHANGELOG.md"

built_at_utc="$(date -u "+%Y-%m-%dT%H:%M:%SZ")"
if [ -n "$SOURCE_DATE_EPOCH" ]; then
  # macOS `date` doesn't support -d, so use python if present.
  if command -v python3 >/dev/null 2>&1; then
    built_at_utc="$(
      python3 - <<'PY'
import os
import datetime

s = os.environ.get("SOURCE_DATE_EPOCH", "")
try:
  e = int(s)
  print(datetime.datetime.fromtimestamp(e, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
except Exception:
  print("unknown")
PY
    )"
  else
    built_at_utc="unknown"
  fi
fi

cat >"$dist_dir/BUILD_INFO.txt" <<EOF
hxhx build artifact

Version: $version
Platform: $platform
Arch: $arch
Built at (UTC): $built_at_utc
SOURCE_DATE_EPOCH: ${SOURCE_DATE_EPOCH:-unset}
Stage0 Haxe: $("$HAXE_BIN" -version 2>/dev/null || "$HAXE_BIN" --version 2>/dev/null || echo unknown)
OCaml: $(ocamlc -version 2>/dev/null || echo unknown)
Dune: $(dune --version 2>/dev/null || echo unknown)
EOF

artifact="hxhx-$version-$platform-$arch.tar.gz"
artifact_path="$dist_root/$artifact"
rm -f "$artifact_path" "$artifact_path.sha256"

echo "== Packaging $artifact"
tar_is_gnu=0
if tar --version 2>/dev/null | head -n 1 | grep -qi "gnu tar"; then
  tar_is_gnu=1
fi
(
  cd "$dist_dir/.."
  if [ "$tar_is_gnu" -eq 1 ]; then
    tar_mtime=()
    if [ -n "$SOURCE_DATE_EPOCH" ]; then
      tar_mtime=(--mtime="@${SOURCE_DATE_EPOCH}")
    fi
    tar --sort=name --owner=0 --group=0 --numeric-owner "${tar_mtime[@]}" -czf "$artifact_path" "$(basename "$dist_dir")"
  else
    # Best-effort on non-GNU tar (e.g. bsdtar on macOS). Layout is stable, but the gzip stream may not be bit-reproducible.
    tar -czf "$artifact_path" "$(basename "$dist_dir")"
  fi
)

"${checksum_cmd[@]}" "$artifact_path" >"$artifact_path.sha256"

echo "OK: $artifact_path"
