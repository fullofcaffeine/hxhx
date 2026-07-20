#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HAXE_BIN="${HAXE_BIN:-haxe}"
REFLAXE_SOURCE_ROOT="${REFLAXE_SOURCE_ROOT:-}"

if [ -z "$REFLAXE_SOURCE_ROOT" ]; then
  reflaxe_hxml="$ROOT/haxe_libraries/reflaxe.hxml"
  reflaxe_classpath="$(awk '$1 == "-cp" { print $2; exit }' "$reflaxe_hxml")"
  if [ -n "$reflaxe_classpath" ]; then
    haxe_libcache="${HAXE_LIBCACHE:-${HOME}/haxe/haxe_libraries}"
    reflaxe_classpath="${reflaxe_classpath//'${HAXE_LIBCACHE}'/$haxe_libcache}"
    if [ -d "$reflaxe_classpath" ]; then
      REFLAXE_SOURCE_ROOT="$(cd "$reflaxe_classpath/.." && pwd)"
    fi
  fi
fi

if [ -z "$REFLAXE_SOURCE_ROOT" ]; then
  reflaxe_classpath="$(haxelib path reflaxe 2>/dev/null | awk 'NF && $1 !~ /^-/ { print; exit }')"
  if [ -n "$reflaxe_classpath" ] && [ -d "$reflaxe_classpath" ]; then
    REFLAXE_SOURCE_ROOT="$(cd "$reflaxe_classpath/.." && pwd)"
  fi
fi

if [ -z "$REFLAXE_SOURCE_ROOT" ] || [ ! -f "$REFLAXE_SOURCE_ROOT/src/reflaxe/ReflectCompiler.hx" ]; then
  echo "Unable to resolve a Reflaxe source root; set REFLAXE_SOURCE_ROOT to a reviewed checkout." >&2
  exit 2
fi

if [ ! -f "$REFLAXE_SOURCE_ROOT/src/reflaxe/preprocessors/implementations/RemovePureExpressionsImpl.hx" ]; then
  echo "Resolved Reflaxe does not contain RemovePureExpressionsImpl." >&2
  echo "Set REFLAXE_SOURCE_ROOT to the reviewed framework checkout instead of relying on a same-version stale cache." >&2
  exit 2
fi

macro_output="$($HAXE_BIN \
  -cp "$REFLAXE_SOURCE_ROOT/src" \
  -cp "$ROOT/test/reflaxe_ocaml_preprocessor_lifecycle/src" \
  --macro 'ReflaxeOcamlPreprocessorLifecycleTest.verifyMarkerLoss()' \
  -main ReflaxeOcamlPreprocessorLifecycleTest \
  --interp)"

if [ "$macro_output" != "REFLAXE_REMOVE_PURE_MARKER_LOSS:CONFIRMED" ]; then
  echo "Unexpected Reflaxe marker-loss probe output: $macro_output" >&2
  exit 1
fi

REFLAXE_SOURCE_ROOT="$REFLAXE_SOURCE_ROOT" \
PORTABLE_FIXTURE_ALLOWLIST=place_standalone_update_lifecycle \
  bash "$ROOT/scripts/test-portable.sh"

echo "REFLAXE_OCAML_PREPROCESSOR_LIFECYCLE:PASS"
