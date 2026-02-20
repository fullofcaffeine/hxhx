#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE_ROOTS_RAW="${HXHX_EXAMPLE_ROOTS:-examples:packages/reflaxe.ocaml/examples}"

read_example_roots() {
  local raw="$1"
  local -a roots=()
  IFS=':' read -r -a roots <<<"$raw"
  for root in "${roots[@]}"; do
    root="$(echo "$root" | xargs || true)"
    [ -n "$root" ] || continue
    [ -d "$root" ] || continue
    echo "$root"
  done
}

collect_example_dirs() {
  local -a roots=("$@")
  for root in "${roots[@]}"; do
    find "$root" -mindepth 1 -maxdepth 1 -type d | sort
  done
}

has_marker_in_roots() {
  local marker="$1"
  shift
  local -a roots=("$@")
  for root in "${roots[@]}"; do
    if find "$root" -maxdepth 2 -type f -name "$marker" -print -quit | grep -q .; then
      return 0
    fi
  done
  return 1
}

EXAMPLE_ROOTS=()
while IFS= read -r root; do
  EXAMPLE_ROOTS+=("$root")
done < <(read_example_roots "$EXAMPLE_ROOTS_RAW")
if [ "${#EXAMPLE_ROOTS[@]}" -eq 0 ]; then
  echo "No example roots found. Set HXHX_EXAMPLE_ROOTS or restore example directories." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping examples: dune/ocamlc not found on PATH."
  exit 0
fi

check_findlib_packages() {
  local dir="$1"
  local req_file="${dir}/OCAML_FINDLIB_PACKAGES"
  [ -f "$req_file" ] || return 0

  if ! command -v ocamlfind >/dev/null 2>&1; then
    echo "Skipping example (missing ocamlfind): ${dir}"
    return 1
  fi

  local missing=0
  while IFS= read -r line; do
    # Strip comments and trim.
    line="${line%%#*}"
    line="$(echo "$line" | xargs || true)"
    [ -n "$line" ] || continue
    for pkg in $line; do
      if ! ocamlfind query "$pkg" >/dev/null 2>&1; then
        echo "Skipping example (missing OCaml findlib package '$pkg'): ${dir}"
        missing=1
      fi
    done
  done < "$req_file"

  [ "$missing" -eq 0 ]
}

build_hxhx_if_needed() {
  # If any example declares it needs hxhx, build it once and export HXHX_EXE.
  #
  # Markers:
  # - USE_HXHX: run the example via `hxhx --target ocaml` (stage0 shim path).
  # - USE_HXHX_STAGE3: run the example via `hxhx --hxhx-stage3` (bring-up path).
  # - USE_HXHX_JS: run the example via `hxhx --target js`.
  if ! has_marker_in_roots "USE_HXHX" "${EXAMPLE_ROOTS[@]}" \
    && ! has_marker_in_roots "USE_HXHX_STAGE3" "${EXAMPLE_ROOTS[@]}" \
    && ! has_marker_in_roots "USE_HXHX_JS" "${EXAMPLE_ROOTS[@]}"; then
    return 0
  fi

  if [ -n "${HXHX_EXE:-}" ] && [ -f "${HXHX_EXE:-}" ]; then
    return 0
  fi

  echo "== Building hxhx (for USE_HXHX examples)"
  HXHX_EXE="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
  if [ -z "$HXHX_EXE" ] || [ ! -f "$HXHX_EXE" ]; then
    echo "Missing built executable from build-hxhx.sh (expected a path to an .exe)." >&2
    exit 1
  fi
  export HXHX_EXE

  # If any example needs Stage3, also build the macro host once (stage0-free via bootstrap snapshot)
  # and export HXHX_MACRO_HOST_EXE so `--macro ...` can run.
  if has_marker_in_roots "USE_HXHX_STAGE3" "${EXAMPLE_ROOTS[@]}"; then
    if ! command -v ocamlopt >/dev/null 2>&1; then
      echo "Skipping Stage3 examples: ocamlopt not found on PATH."
      return 0
    fi

    echo "== Building hxhx macro host (for USE_HXHX_STAGE3 examples)"
    HXHX_MACRO_HOST_EXE="$(bash scripts/hxhx/build-hxhx-macro-host.sh | tail -n 1)"
    if [ -z "$HXHX_MACRO_HOST_EXE" ] || [ ! -f "$HXHX_MACRO_HOST_EXE" ]; then
      echo "Missing built executable from build-hxhx-macro-host.sh (expected a path to an .exe)." >&2
      exit 1
    fi
    export HXHX_MACRO_HOST_EXE
  fi
}

build_hxhx_if_needed

run_example_setup() {
  local setup_script="setup-lix.sh"
  [ -f "$setup_script" ] || return 0

  if ! command -v lix >/dev/null 2>&1; then
    echo "Skipping example (missing lix): $(pwd)"
    return 1
  fi

  bash "$setup_script"
}

apply_example_env() {
  local env_file="EXAMPLE_ENV"
  [ -f "$env_file" ] || return 0

  # Parse `KEY=value` lines.
  #
  # Notes
  # - Keep this minimal and deterministic (do not `source` arbitrary shell).
  # - Values are interpreted relative to the example directory to keep paths portable.
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs || true)"
    [ -n "$line" ] || continue
    case "$line" in
      *=*)
        local k="${line%%=*}"
        local v="${line#*=}"
        export "${k}=${v}"
        ;;
      *)
        echo "Ignoring malformed EXAMPLE_ENV line in $(pwd): ${line}" >&2
        ;;
    esac
  done < "$env_file"
}

EXAMPLE_DIRS=()
while IFS= read -r dir; do
  EXAMPLE_DIRS+=("$dir")
done < <(collect_example_dirs "${EXAMPLE_ROOTS[@]}")
for dir in "${EXAMPLE_DIRS[@]}"; do
  [ -f "${dir}/build.hxml" ] || continue
  if [ -f "${dir}/ACCEPTANCE_ONLY" ]; then
    if [ "${ONLY_ACCEPTANCE_EXAMPLES:-0}" = "1" ]; then
      :
    elif [ "${RUN_ACCEPTANCE_EXAMPLES:-0}" = "1" ]; then
      :
    else
      echo "Skipping acceptance example: ${dir}"
      continue
    fi
  else
    if [ "${ONLY_ACCEPTANCE_EXAMPLES:-0}" = "1" ]; then
      continue
    fi
  fi

  if ! check_findlib_packages "$dir"; then
    continue
  fi

  echo "== Example: ${dir}/"

  (
    cd "$dir"
    rm -rf out
    mkdir -p out

    if ! run_example_setup; then
      exit 0
    fi

    apply_example_env

    artifact=""
    run_cmd=()
    if [ -f "USE_HXHX_STAGE3" ]; then
      if ! command -v ocamlopt >/dev/null 2>&1; then
        echo "Skipping Stage3 example (missing ocamlopt): ${dir}"
        exit 0
      fi
      # Stage3 emits `out/out.exe` directly (no dune project).
      #
      # Use `--hxhx-no-run` so we can capture runtime output deterministically below.
      #
      # Some bring-up examples can provide `STAGE3_ARGS` (one argument per line)
      # to bypass known Stage3 HXML parsing gaps while still exercising the same
      # compilation workload under Stage3.
      stage3_args=()
      if [ -f "STAGE3_ARGS" ]; then
        while IFS= read -r line; do
          line="${line%%#*}"
          line="$(echo "$line" | xargs || true)"
          [ -n "$line" ] || continue
          stage3_args+=("$line")
        done < "STAGE3_ARGS"
      fi
      if [ "${#stage3_args[@]}" -eq 0 ]; then
        stage3_args=(build.hxml)
      fi
      HXHX_REPO_ROOT="$ROOT" HAXE_BIN="$HAXE_BIN" "$HXHX_EXE" --hxhx-stage3 --hxhx-no-run --hxhx-emit-full-bodies --hxhx-out out "${stage3_args[@]}" -D ocaml_build=native
      artifact="out/out.exe"
      run_cmd=("./$artifact")
    elif [ -f "USE_HXHX_JS" ]; then
      if ! command -v node >/dev/null 2>&1; then
        echo "Skipping JS example (missing node): ${dir}"
        exit 0
      fi
      HXHX_REPO_ROOT="$ROOT" HAXE_BIN="$HAXE_BIN" "$HXHX_EXE" --target js build.hxml --js out/main.js
      artifact="out/main.js"
      run_cmd=(node -e "global.window={console:console};global.document={getElementById:function(){return null;}};global.window.document=global.document;global.navigator={};require('./${artifact}');")
    elif [ -f "USE_HXHX" ]; then
      HXHX_REPO_ROOT="$ROOT" HAXE_BIN="$HAXE_BIN" "$HXHX_EXE" --target ocaml build.hxml -D ocaml_build=native
      artifact="out/_build/default/out.exe"
      run_cmd=("./$artifact")
    else
      "$HAXE_BIN" build.hxml -D ocaml_build=native
      artifact="out/_build/default/out.exe"
      run_cmd=("./$artifact")
    fi

    if [ ! -f "$artifact" ]; then
      echo "Missing built artifact: ${dir}/$artifact" >&2
      exit 1
    fi

    tmp="$(mktemp)"
    HX_TEST_ENV=ok "${run_cmd[@]}" > "$tmp"
    diff -u "expected.stdout" "$tmp"
    rm -f "$tmp"
  )
done
