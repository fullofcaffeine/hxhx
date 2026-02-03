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
    "$HAXE_BIN" build.hxml -D ocaml_build=native
  )

  exe="${dir}out/_build/default/out.exe"
  if [ ! -f "$exe" ]; then
    echo "Missing built executable: $exe" >&2
    exit 1
  fi

  tmp="$(mktemp)"
  HX_TEST_ENV=ok "$exe" > "$tmp"
  diff -u "${dir}expected.stdout" "$tmp"
  rm -f "$tmp"
done
