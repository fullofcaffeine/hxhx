#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
PORTABLE_NATIVE_SURFACE_STRICT="${PORTABLE_NATIVE_SURFACE_STRICT:-0}"
PORTABLE_FIXTURE_ALLOWLIST="${PORTABLE_FIXTURE_ALLOWLIST:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="$ROOT/test/portable/fixtures"
PORTABLE_FIXTURE_ALLOWLIST_NORM=""

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi
  echo "Missing SHA-256 tool (need sha256sum or shasum)." >&2
  return 1
}

if [ -n "$PORTABLE_FIXTURE_ALLOWLIST" ]; then
  PORTABLE_FIXTURE_ALLOWLIST_NORM=","
  while IFS= read -r fixture_name || [ -n "$fixture_name" ]; do
    fixture_name="${fixture_name//[[:space:]]/}"
    [ -n "$fixture_name" ] || continue
    PORTABLE_FIXTURE_ALLOWLIST_NORM="${PORTABLE_FIXTURE_ALLOWLIST_NORM}${fixture_name},"
  done < <(printf '%s' "$PORTABLE_FIXTURE_ALLOWLIST" | tr ',' '\n')
fi

if [ ! -d "$FIXTURE_ROOT" ]; then
  echo "No portable fixtures directory found at $FIXTURE_ROOT" >&2
  exit 1
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping portable conformance: dune/ocamlc not found on PATH."
  exit 0
fi

run_count=0
for dir in "$FIXTURE_ROOT"/*/; do
  [ -f "${dir}build.hxml" ] || continue
  fixture_name="$(basename "$dir")"
  if [ -n "$PORTABLE_FIXTURE_ALLOWLIST_NORM" ] && [[ "$PORTABLE_FIXTURE_ALLOWLIST_NORM" != *",$fixture_name,"* ]]; then
    continue
  fi
  run_count=$((run_count + 1))
  echo "== Portable: ${dir#"$ROOT/"}"

  (
    cd "$dir"
    rm -rf out
    mkdir -p out
    if [ "$PORTABLE_NATIVE_SURFACE_STRICT" = "1" ]; then
      "$HAXE_BIN" build.hxml -D ocaml_build=native -D ocaml_portable_native_surface=error
    else
      "$HAXE_BIN" build.hxml -D ocaml_build=native
    fi
  )

  if [ -f "${dir}expected.lowering.json" ]; then
    lowering_report="${dir}out/ocaml_lowering_report.json"
    if [ ! -f "$lowering_report" ]; then
      echo "Missing lowered semantic report: $lowering_report" >&2
      exit 1
    fi
    diff -u "${dir}expected.lowering.json" "$lowering_report"
    first_lowering_checksum="$(sha256_file "$lowering_report")"
    (
      cd "$dir"
      if [ "$PORTABLE_NATIVE_SURFACE_STRICT" = "1" ]; then
        "$HAXE_BIN" build.hxml -D ocaml_build=native -D ocaml_portable_native_surface=error
      else
        "$HAXE_BIN" build.hxml -D ocaml_build=native
      fi
    )
    second_lowering_checksum="$(sha256_file "$lowering_report")"
    if [ "$first_lowering_checksum" != "$second_lowering_checksum" ]; then
      echo "Lowered semantic report is not deterministic for ${dir#"$ROOT/"}: $first_lowering_checksum != $second_lowering_checksum" >&2
      exit 1
    fi
    diff -u "${dir}expected.lowering.json" "$lowering_report"
  fi

  exe="${dir}out/_build/default/out.exe"
  if [ ! -f "$exe" ]; then
    echo "Missing built executable: $exe" >&2
    exit 1
  fi

  out_tmp="$(mktemp)"
  err_tmp="$(mktemp)"
  if [ -f "${dir}stdin.txt" ]; then
    if env -u HX_TEST_ENV_MISSING_REFLAXE_OCAML HX_TEST_ENV=ok "$exe" <"${dir}stdin.txt" >"$out_tmp" 2>"$err_tmp"; then
      :
    else
      status=$?
      echo "Portable fixture process failed: ${dir#"$ROOT/"} (exit $status)" >&2
      if [ -s "$out_tmp" ]; then
        echo "--- stdout ---" >&2
        cat "$out_tmp" >&2
      fi
      if [ -s "$err_tmp" ]; then
        echo "--- stderr ---" >&2
        cat "$err_tmp" >&2
      fi
      exit "$status"
    fi
  else
    if env -u HX_TEST_ENV_MISSING_REFLAXE_OCAML HX_TEST_ENV=ok "$exe" >"$out_tmp" 2>"$err_tmp"; then
      :
    else
      status=$?
      echo "Portable fixture process failed: ${dir#"$ROOT/"} (exit $status)" >&2
      if [ -s "$out_tmp" ]; then
        echo "--- stdout ---" >&2
        cat "$out_tmp" >&2
      fi
      if [ -s "$err_tmp" ]; then
        echo "--- stderr ---" >&2
        cat "$err_tmp" >&2
      fi
      exit "$status"
    fi
  fi

  diff -u "${dir}expected.stdout" "$out_tmp"

  if [ -f "${dir}expected.stderr" ]; then
    diff -u "${dir}expected.stderr" "$err_tmp"
  else
    if [ -s "$err_tmp" ]; then
      echo "Unexpected stderr for fixture ${dir#"$ROOT/"}:" >&2
      cat "$err_tmp" >&2
      exit 1
    fi
  fi

  rm -f "$out_tmp" "$err_tmp"
done

if [ -n "$PORTABLE_FIXTURE_ALLOWLIST_NORM" ] && [ "$run_count" -eq 0 ]; then
  echo "No matching fixtures for PORTABLE_FIXTURE_ALLOWLIST=$PORTABLE_FIXTURE_ALLOWLIST" >&2
  exit 2
fi

echo "✓ Portable conformance OK"
