#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}"
HXHX_DIST_FORBID_STAGE0="${HXHX_DIST_FORBID_STAGE0:-1}"

is_true() {
  local v="${1:-}"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

case "$HXHX_DIST_FORBID_STAGE0" in
  0|1|true|false|yes|no|on|off) ;;
  *)
    echo "Invalid HXHX_DIST_FORBID_STAGE0: $HXHX_DIST_FORBID_STAGE0 (expected boolean-like value)." >&2
    exit 2
    ;;
esac

DIST_FORBID_STAGE0=0
if is_true "$HXHX_DIST_FORBID_STAGE0"; then
  DIST_FORBID_STAGE0=1
fi

if [ "$DIST_FORBID_STAGE0" -eq 0 ] && ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if [ "$DIST_FORBID_STAGE0" -eq 1 ]; then
  if is_true "${HXHX_FORCE_STAGE0:-0}"; then
    echo "Dist stage0 policy violation: HXHX_FORCE_STAGE0=1 is not allowed when HXHX_DIST_FORBID_STAGE0=1." >&2
    exit 1
  fi
  if is_true "${HXHX_MACRO_HOST_FORCE_STAGE0:-0}"; then
    echo "Dist stage0 policy violation: HXHX_MACRO_HOST_FORCE_STAGE0=1 is not allowed when HXHX_DIST_FORBID_STAGE0=1." >&2
    exit 1
  fi
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
if [ "$DIST_FORBID_STAGE0" -eq 1 ]; then
  HXHX_BIN="$(HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
else
  HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
fi
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Missing built executable from build-hxhx.sh (expected a path to an .exe)." >&2
  exit 1
fi

cp "$HXHX_BIN" "$bin_dir/hxhx"
chmod +x "$bin_dir/hxhx"

echo "== Building hxhx macro host binary"
if [ "$DIST_FORBID_STAGE0" -eq 1 ]; then
  HXHX_MACRO_HOST_BIN="$(HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
else
  HXHX_MACRO_HOST_BIN="$("$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1)"
fi
if [ -z "$HXHX_MACRO_HOST_BIN" ] || [ ! -f "$HXHX_MACRO_HOST_BIN" ]; then
  echo "Missing built executable from build-hxhx-macro-host.sh (expected a path to an .exe)." >&2
  exit 1
fi

cp "$HXHX_MACRO_HOST_BIN" "$bin_dir/hxhx-macro-host"
chmod +x "$bin_dir/hxhx-macro-host"

cp "$ROOT/README.md" "$dist_dir/README.md"
cp "$ROOT/LICENSE" "$dist_dir/LICENSE"
cp "$ROOT/CHANGELOG.md" "$dist_dir/CHANGELOG.md"

if ! grep -q "Permission is hereby granted" "$dist_dir/LICENSE"; then
  echo "Dist LICENSE does not look like MIT (missing 'Permission is hereby granted')." >&2
  exit 1
fi

echo "== Bundling backend sources (best-effort)"
lib_dir="$dist_dir/lib"
mkdir -p "$lib_dir"

# Bundle reflaxe.ocaml (this repo) sources so delegated `hxhx --ocaml-eval` can work without haxelib.
mkdir -p "$lib_dir/reflaxe.ocaml"
cp -R "$ROOT/packages/reflaxe.ocaml/src" "$lib_dir/reflaxe.ocaml/src"
cp -R "$ROOT/packages/reflaxe.ocaml/std" "$lib_dir/reflaxe.ocaml/std"
cp "$ROOT/packages/reflaxe.ocaml/haxelib.json" "$lib_dir/reflaxe.ocaml/haxelib.json"
cp "$ROOT/packages/reflaxe.ocaml/extraParams.hxml" "$lib_dir/reflaxe.ocaml/extraParams.hxml"

# Bundle reflaxe dependency sources (required for CompilerInit/ReflectCompiler macros).
if command -v haxelib >/dev/null 2>&1; then
  reflaxe_src="$(haxelib path reflaxe 2>/dev/null | head -n 1 || true)"
  if [ -n "$reflaxe_src" ] && [ -d "$reflaxe_src" ]; then
    reflaxe_root="$(cd "$(dirname "$reflaxe_src")/.." && pwd)"
    mkdir -p "$lib_dir/reflaxe"
    if [ -d "$reflaxe_root/src" ]; then
      cp -R "$reflaxe_root/src" "$lib_dir/reflaxe/src"
    else
      echo "Note: reflaxe resolved, but src/ missing at $reflaxe_root/src; dist will require -lib reflaxe to be available."
    fi
    cp "$reflaxe_root/haxelib.json" "$lib_dir/reflaxe/haxelib.json" 2>/dev/null || true
    cp "$reflaxe_root/extraParams.hxml" "$lib_dir/reflaxe/extraParams.hxml" 2>/dev/null || true
    cp "$reflaxe_root/LICENSE" "$lib_dir/reflaxe/LICENSE" 2>/dev/null || true
  else
    echo "Note: could not resolve reflaxe via haxelib path; dist will require -lib reflaxe to be available."
  fi
else
  echo "Note: haxelib not found; dist will require -lib reflaxe to be available."
fi

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
Stage0 Haxe: $(
if [ "$DIST_FORBID_STAGE0" -eq 1 ]; then
  echo "forbidden (HXHX_DIST_FORBID_STAGE0=1)"
else
  "$HAXE_BIN" -version 2>/dev/null || "$HAXE_BIN" --version 2>/dev/null || echo unknown
fi
)
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
