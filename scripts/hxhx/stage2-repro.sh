#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HAXE_BIN="${HAXE_BIN:-haxe}"

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping Stage2 check: dune/ocamlc not found on PATH."
  exit 0
fi

if ! command -v shasum >/dev/null 2>&1; then
  echo "Skipping Stage2 check: shasum not found on PATH (used for output comparison)." >&2
  exit 0
fi

echo "== Stage2 reproducibility check: stage1 builds stage2"

echo "-- Building stage1 (using stage0 $HAXE_BIN)"
STAGE1_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
if [ -z "$STAGE1_BIN" ] || [ ! -f "$STAGE1_BIN" ]; then
  echo "Failed to build stage1 (missing binary path)." >&2
  exit 1
fi

echo "-- Building stage2 (using stage1 $STAGE1_BIN)"
STAGE2_OUT_DIR="$ROOT/examples/hxhx/out_stage2"
(
  cd "$ROOT/examples/hxhx"
  rm -rf out_stage2 || true
  mkdir -p out_stage2
  # `build.hxml` already emits to `out/`; override so we keep stage1 and stage2 separate.
  "$STAGE1_BIN" build.hxml -D ocaml_output=out_stage2 -D ocaml_build=native
)

STAGE2_BIN=""
if [ -d "$STAGE2_OUT_DIR/_build/default" ]; then
  # Dune executable name is derived from output dir name (see DuneProjectEmitter.defaultExeName),
  # so we locate the produced `*.exe` rather than hard-coding `out.exe`.
  shopt -s nullglob
  candidates=("$STAGE2_OUT_DIR/_build/default/"*.exe)
  shopt -u nullglob
  if [ "${#candidates[@]}" -ge 1 ] && [ -f "${candidates[0]}" ]; then
    STAGE2_BIN="${candidates[0]}"
  fi
fi

if [ -z "$STAGE2_BIN" ] || [ ! -f "$STAGE2_BIN" ]; then
  echo "Stage2 build succeeded but did not produce an executable under: $STAGE2_OUT_DIR/_build/default" >&2
  exit 1
fi

echo "-- Behavioral equivalence (shim surface)"
stage1_ok="$("$STAGE1_BIN")"
stage2_ok="$("$STAGE2_BIN")"
if [ "$stage1_ok" != "$stage2_ok" ]; then
  echo "Mismatch running with no args:" >&2
  echo "stage1: $stage1_ok" >&2
  echo "stage2: $stage2_ok" >&2
  exit 1
fi

stage1_help="$("$STAGE1_BIN" --hxhx-help)"
stage2_help="$("$STAGE2_BIN" --hxhx-help)"
if [ "$stage1_help" != "$stage2_help" ]; then
  echo "Mismatch for --hxhx-help output." >&2
  exit 1
fi

stage1_ver="$("$STAGE1_BIN" --version)"
stage2_ver="$("$STAGE2_BIN" --version)"
if [ "$stage1_ver" != "$stage2_ver" ]; then
  echo "Mismatch for --version output (expected stage0 passthrough)." >&2
  echo "stage1: $stage1_ver" >&2
  echo "stage2: $stage2_ver" >&2
  exit 1
fi

if ! echo "$stage1_ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+'; then
  echo "Unexpected --version output (not SemVer-ish): $stage1_ver" >&2
  exit 1
fi

echo "-- Output reproducibility (OCaml emit) [best-effort]"
tmp_root="$(mktemp -d)"
stage1_out="$tmp_root/stage1_out"
stage2_out="$tmp_root/stage2_out"
mkdir -p "$tmp_root/src"
cat >"$tmp_root/src/Main.hx" <<'HX'
class Main {
  static function main() {
    Sys.println("OK stage2");
  }
}
HX

compile_emit_only() {
  local compiler="$1"
  local out="$2"
  mkdir -p "$out"
  "$compiler" -cp "$tmp_root/src" -main Main --no-output -lib reflaxe.ocaml -D no_traces -D ocaml_output="$out" -D ocaml_no_build
}

compile_emit_only "$STAGE1_BIN" "$stage1_out"
compile_emit_only "$STAGE2_BIN" "$stage2_out"

hash_tree() {
  local dir="$1"
  local base
  base="$(basename "$dir")"
	  find "$dir" -type f -name '*.ml' -print0 \
	    | sort -z \
	    | xargs -0 shasum -a 256 \
	    | sed "s#  $dir/#  #" \
	    | grep -v "  ${base}\\.ml\$"
}

stage1_hashes="$(hash_tree "$stage1_out")"
stage2_hashes="$(hash_tree "$stage2_out")"
if [ "$stage1_hashes" != "$stage2_hashes" ]; then
  echo "Mismatch in emitted .ml files (stage1 vs stage2). This can be expected once hxhx stops being a shim," >&2
  echo "but for the current stage0 shim it indicates a regression." >&2
  diff -u <(printf '%s\n' "$stage1_hashes") <(printf '%s\n' "$stage2_hashes") || true
  exit 1
fi

echo "OK: stage1 and stage2 are reproducible enough (behavior + .ml hashes match)"
