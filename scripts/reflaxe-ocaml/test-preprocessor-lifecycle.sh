#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
REFLAXE_SOURCE_ROOT="${REFLAXE_SOURCE_ROOT:-}"

if [ -z "$REFLAXE_SOURCE_ROOT" ]; then
  reflaxe_hxml="$ROOT/haxe_libraries/reflaxe.hxml"
  reflaxe_classpath="$(awk '$1 == "-cp" { print $2; exit }' "$reflaxe_hxml")"
  if [ -z "$reflaxe_classpath" ]; then
    echo "Committed haxe_libraries/reflaxe.hxml does not declare a classpath." >&2
    exit 2
  fi
  haxe_libcache="${HAXE_LIBCACHE:-${HOME}/haxe/haxe_libraries}"
  reflaxe_classpath="${reflaxe_classpath//'${HAXE_LIBCACHE}'/$haxe_libcache}"
  if [ -d "$reflaxe_classpath" ]; then
    REFLAXE_SOURCE_ROOT="$(cd "$reflaxe_classpath/.." && pwd)"
  else
    echo "Pinned Reflaxe framework is not downloaded at $reflaxe_classpath; run npx lix download." >&2
    exit 2
  fi
fi

if [ -z "$REFLAXE_SOURCE_ROOT" ] || [ ! -f "$REFLAXE_SOURCE_ROOT/src/reflaxe/ReflectCompiler.hx" ]; then
  echo "Unable to resolve a Reflaxe source root; set REFLAXE_SOURCE_ROOT to a reviewed checkout." >&2
  exit 2
fi

if [ ! -f "$REFLAXE_SOURCE_ROOT/src/reflaxe/preprocessors/implementations/RemovePureExpressionsImpl.hx" ]; then
  echo "Resolved Reflaxe does not contain RemovePureExpressionsImpl." >&2
  echo "Use the committed immutable Reflaxe mapping or set REFLAXE_SOURCE_ROOT explicitly." >&2
  exit 2
fi

macro_output="$($HAXE_BIN \
  -cp "$REFLAXE_SOURCE_ROOT/src" \
  -cp "$ROOT/test/reflaxe_ocaml_preprocessor_lifecycle/src" \
  --macro 'ReflaxeOcamlPreprocessorLifecycleTest.verifyMarkerPreservation()' \
  -main ReflaxeOcamlPreprocessorLifecycleTest \
  --interp)"

if [ "$macro_output" != "REFLAXE_REMOVE_PURE_MARKER_PRESERVATION:CONFIRMED" ]; then
  echo "Unexpected Reflaxe marker-preservation probe output: $macro_output" >&2
  exit 1
fi

REFLAXE_SOURCE_ROOT="$REFLAXE_SOURCE_ROOT" \
PORTABLE_FIXTURE_ALLOWLIST=place_standalone_update_lifecycle \
  bash "$ROOT/scripts/test-portable.sh"

echo "REFLAXE_OCAML_PREPROCESSOR_LIFECYCLE:PASS"
