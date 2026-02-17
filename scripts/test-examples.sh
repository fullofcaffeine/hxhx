#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping examples: dune/ocamlc not found on PATH."
  exit 0
fi

check_findlib_packages() {
  local dir="$1"
  local req_file="${dir}OCAML_FINDLIB_PACKAGES"
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
  if ! find examples -maxdepth 2 -type f \( -name "USE_HXHX" -o -name "USE_HXHX_STAGE3" \) -print -quit | grep -q .; then
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
  if find examples -maxdepth 2 -type f -name "USE_HXHX_STAGE3" -print -quit | grep -q .; then
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

for dir in examples/*/; do
  [ -f "${dir}build.hxml" ] || continue
  if [ -f "${dir}ACCEPTANCE_ONLY" ]; then
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

  echo "== Example: ${dir}"

  (
    cd "$dir"
    rm -rf out
    mkdir -p out

    apply_example_env

    exe=""
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
      HAXE_BIN="$HAXE_BIN" "$HXHX_EXE" --hxhx-stage3 --hxhx-no-run --hxhx-emit-full-bodies --hxhx-out out "${stage3_args[@]}" -D ocaml_build=native
      exe="out/out.exe"
    elif [ -f "USE_HXHX" ]; then
      HAXE_BIN="$HAXE_BIN" "$HXHX_EXE" --target ocaml build.hxml -D ocaml_build=native
      exe="out/_build/default/out.exe"
    else
      "$HAXE_BIN" build.hxml -D ocaml_build=native
      exe="out/_build/default/out.exe"
    fi

    if [ ! -f "$exe" ]; then
      echo "Missing built executable: ${dir}${exe}" >&2
      exit 1
    fi

    tmp="$(mktemp)"
    HX_TEST_ENV=ok "./$exe" > "$tmp"
    diff -u "expected.stdout" "$tmp"
    rm -f "$tmp"
  )
done
