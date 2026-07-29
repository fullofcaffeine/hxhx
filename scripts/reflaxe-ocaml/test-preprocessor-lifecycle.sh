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

pipeline_source="$ROOT/packages/reflaxe.ocaml/src/reflaxe/ocaml/lowered/OcamlFunctionPlanRegistry.hx"
pipeline_revision="$(sed -n 's/.*PIPELINE_REVISION = "\([^"]*\)";.*/\1/p' "$pipeline_source")"
if [ -z "$pipeline_revision" ]; then
  echo "Unable to read the current OCaml function-plan pipeline revision from $pipeline_source." >&2
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
PORTABLE_FIXTURE_ALLOWLIST=place_standalone_update_lifecycle,place_feature_gated_update_lifecycle \
  bash "$ROOT/scripts/test-portable.sh"

fixture_dir="$ROOT/test/portable/fixtures/place_standalone_update_lifecycle"
trace_file="$fixture_dir/out/ocaml_semantic_lifecycle_trace.json"
expected_function='Counter|instance|function|increment'
if [ ! -f "$trace_file" ]; then
  echo "Missing semantic lifecycle trace: $trace_file" >&2
  exit 1
fi
node "$ROOT/scripts/reflaxe-ocaml/verify-semantic-lifecycle-trace.js" "$trace_file" "$expected_function" "$pipeline_revision"

feature_fixture_dir="$ROOT/test/portable/fixtures/place_feature_gated_update_lifecycle"
feature_trace="$feature_fixture_dir/out/ocaml_semantic_lifecycle_trace.json"
feature_function='FeatureGate|instance|function|gatedUpdate'
if [ ! -f "$feature_trace" ]; then
  echo "Missing feature-gated semantic lifecycle trace: $feature_trace" >&2
  exit 1
fi
node "$ROOT/scripts/reflaxe-ocaml/verify-semantic-lifecycle-trace.js" "$feature_trace" "$feature_function" "$pipeline_revision"
if ! rg -Fq 'let featuregate_gatedUpdate =' "$feature_fixture_dir/out/Main.ml"; then
  echo "DCE did not retain the feature-gated update in generated OCaml." >&2
  exit 1
fi

first_trace="$(mktemp)"
negative_output="$(mktemp -d)"
negative_log="$(mktemp)"
cleanup() {
  rm -f "$first_trace" "$negative_log"
  rm -rf "$negative_output"
}
trap cleanup EXIT
cp "$trace_file" "$first_trace"
(
  cd "$fixture_dir"
  if [ -n "$REFLAXE_SOURCE_ROOT" ]; then
    "$HAXE_BIN" build.hxml -cp "$REFLAXE_SOURCE_ROOT/src"
  else
    "$HAXE_BIN" build.hxml
  fi
)
node "$ROOT/scripts/reflaxe-ocaml/verify-semantic-lifecycle-trace.js" "$trace_file" "$expected_function" "$pipeline_revision"
if ! cmp -s "$first_trace" "$trace_file"; then
  echo "Semantic lifecycle trace changed across identical builds." >&2
  diff -u "$first_trace" "$trace_file" >&2 || true
  exit 1
fi

negative_source="$ROOT/test/reflaxe_ocaml_preprocessor_lifecycle/late_mutation/src"
reflaxe_args=()
if [ -n "$REFLAXE_SOURCE_ROOT" ]; then
  reflaxe_args=(-cp "$REFLAXE_SOURCE_ROOT/src")
fi
if "$HAXE_BIN" \
  -cp "$negative_source" \
  -main Main \
  --no-output \
  -lib reflaxe.ocaml \
  -D no-traces \
  -D no_traces \
  -D "ocaml_output=$negative_output" \
  --macro 'LateBodyMutation.install()' \
  "${reflaxe_args[@]}" >"$negative_log" 2>&1; then
  echo "Late body mutation unexpectedly reached OCaml output." >&2
  exit 1
fi
if ! rg -Fq '[reflaxe:planned-body-revision-mismatch]' "$negative_log"; then
  echo "Late body mutation did not report the expected revision mismatch." >&2
  cat "$negative_log" >&2
  exit 1
fi
if find "$negative_output" -type f -name '*.ml' -print -quit | rg -q .; then
  echo "Late body mutation wrote OCaml source before reporting the mismatch." >&2
  exit 1
fi
echo "REFLAXE_OCAML_LATE_BODY_MUTATION_REJECTED:PASS"

echo "REFLAXE_OCAML_PREPROCESSOR_LIFECYCLE:PASS"
