#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$ROOT/test/fixtures/project-macro-module"
ARTIFACT_DIR="${HXHX_PROJECT_MACRO_ARTIFACT_DIR:-$ROOT/.artifacts/project-macro-module}"
CANDIDATE_COMMIT="${HXHX_CANDIDATE_COMMIT:-}"
EXPR='projectmacro.ProjectMacro.message()'
PLUGIN_ID='hxhx.project-macro.fixture'
HANDLER='projectmacro.ProjectMacroNative.nativeExpansion'
TMP_ROOT="$ROOT/.tmp"
mkdir -p "$TMP_ROOT"
WORK_DIR="$(mktemp -d "$TMP_ROOT/project-macro-module.XXXXXX")"

if [ -z "$CANDIDATE_COMMIT" ]; then
  CANDIDATE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
  if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]; then
    CANDIDATE_COMMIT="${CANDIDATE_COMMIT}-dirty"
  fi
fi

cleanup() {
  if [ "${HXHX_KEEP_LOGS:-0}" = "1" ]; then
    echo "Project macro work directory retained: $WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$ARTIFACT_DIR"
rm -rf "$ARTIFACT_DIR"/*
cd "$ROOT"

for tool in dune ocamlc node haxe; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Project macro module smoke requires '$tool' on PATH." >&2
    exit 1
  fi
done

resolve_hxhx() {
  if [ -n "${HXHX_BIN:-}" ] && [ -f "$HXHX_BIN" ]; then
    printf '%s\n' "$HXHX_BIN"
    return
  fi
  HXHX_FORBID_STAGE0=1 HAXE_BIN=__project_macro_stage0_forbidden__ \
    bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1
}

resolve_macro_host() {
  if [ -n "${HXHX_MACRO_HOST_EXE:-}" ] && [ -x "$HXHX_MACRO_HOST_EXE" ]; then
    printf '%s\n' "$HXHX_MACRO_HOST_EXE"
    return
  fi
  HXHX_FORBID_STAGE0=1 HAXE_BIN=__project_macro_host_stage0_forbidden__ \
    bash "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1
}

HXHX_BIN_RESOLVED="$(resolve_hxhx)"
MACRO_HOST_RESOLVED="$(resolve_macro_host)"
if [ ! -f "$HXHX_BIN_RESOLVED" ]; then
  echo "Project macro module smoke did not resolve an hxhx executable: $HXHX_BIN_RESOLVED" >&2
  exit 1
fi
if [ ! -x "$MACRO_HOST_RESOLVED" ]; then
  echo "Project macro module smoke did not resolve an executable macro host: $MACRO_HOST_RESOLVED" >&2
  exit 1
fi

ORACLE_STDOUT="$ARTIFACT_DIR/oracle.stdout"
(
  cd "$FIXTURE_DIR"
  haxe oracle.hxml
) >"$ORACLE_STDOUT" 2>"$ARTIFACT_DIR/oracle.stderr"
diff -u "$FIXTURE_DIR/expected.stdout" "$ORACLE_STDOUT"
echo "PROJECT_MACRO_MODULE_ORACLE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

PLUGIN_OUT="$WORK_DIR/plugin"
mkdir -p "$PLUGIN_OUT"
HXHX_FORBID_STAGE0=1 \
HAXE_BIN=__project_macro_plugin_stage0_forbidden__ \
"$HXHX_BIN_RESOLVED" \
  --hxhx-stage3 \
  --hxhx-emit-full-bodies \
  --hxhx-no-run \
  -cp "$FIXTURE_DIR/src" \
  -main projectmacro.ProjectMacroNative \
  --hxhx-out "$PLUGIN_OUT" \
  -D ocaml_dune_layout=plugin \
  -D "ocaml_plugin_register_macro=$PLUGIN_ID" \
  -D "ocaml_plugin_macro_expr=$EXPR" \
  -D "ocaml_plugin_macro_handler=$HANDLER" \
  >"$ARTIFACT_DIR/plugin-generate.stdout" \
  2>"$ARTIFACT_DIR/plugin-generate.stderr"

(
  cd "$PLUGIN_OUT"
  dune build ./hxhx_plugin_entry.cma ./hxhx_plugin_entry.cmxs
) >"$ARTIFACT_DIR/plugin-build.stdout" 2>"$ARTIFACT_DIR/plugin-build.stderr"

GENERATED_BYTECODE_PLUGIN="$PLUGIN_OUT/_build/default/hxhx_plugin_entry.cma"
GENERATED_NATIVE_PLUGIN="$PLUGIN_OUT/_build/default/hxhx_plugin_entry.cmxs"
if [ ! -f "$GENERATED_BYTECODE_PLUGIN" ] || [ ! -f "$GENERATED_NATIVE_PLUGIN" ]; then
  echo "Project macro module smoke did not build both plugin forms." >&2
  exit 1
fi

MODULE_ARTIFACT_DIR="$ARTIFACT_DIR/module"
mkdir -p "$MODULE_ARTIFACT_DIR"
BYTECODE_PLUGIN="$MODULE_ARTIFACT_DIR/project-macro.cma"
NATIVE_PLUGIN="$MODULE_ARTIFACT_DIR/project-macro.cmxs"
cp "$GENERATED_BYTECODE_PLUGIN" "$BYTECODE_PLUGIN"
cp "$GENERATED_NATIVE_PLUGIN" "$NATIVE_PLUGIN"
RECEIPT="$MODULE_ARTIFACT_DIR/project-macro-receipt.json"
node "$ROOT/scripts/ci/native-macro-module-receipt.js" write \
  --report "$RECEIPT" \
  --candidate-commit "$CANDIDATE_COMMIT" \
  --plugin-id "$PLUGIN_ID" \
  --expr "$EXPR" \
  --native-artifact "$NATIVE_PLUGIN" \
  --bytecode-artifact "$BYTECODE_PLUGIN" \
  >"$ARTIFACT_DIR/receipt-write.stdout"
node "$ROOT/scripts/ci/native-macro-module-receipt.js" validate \
  --report "$RECEIPT" \
  --expected-candidate "$CANDIDATE_COMMIT" \
  >"$ARTIFACT_DIR/receipt-summary.json"
echo "PROJECT_MACRO_MODULE_BUILD:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

run_mode() {
  local mode="$1"
  local mode_key="${mode//-/_}"
  local mode_marker
  mode_marker="$(printf '%s' "$mode_key" | tr '[:lower:]' '[:upper:]')"
  local out_dir="$WORK_DIR/app-$mode_key"
  local js_path="$out_dir/main.js"
  mkdir -p "$out_dir"
  HXHX_FORBID_STAGE0=1 \
  HAXE_BIN=__project_macro_app_stage0_forbidden__ \
  HXHX_MACRO_RUNTIME_MODE="$mode" \
  HXHX_MACRO_HOST_AUTO_BUILD=0 \
  HXHX_MACRO_HOST_EXE="$MACRO_HOST_RESOLVED" \
  HXHX_NATIVE_MACRO_MODULE_RECEIPT="$RECEIPT" \
  HXHX_CANDIDATE_COMMIT="$CANDIDATE_COMMIT" \
  HXHX_EXPR_MACROS="$EXPR" \
  "$HXHX_BIN_RESOLVED" \
    --hxhx-no-run \
    --js "$js_path" \
    -cp "$FIXTURE_DIR/src" \
    -main Main \
    --hxhx-out "$out_dir" \
    >"$ARTIFACT_DIR/$mode_key.compile.stdout" \
    2>"$ARTIFACT_DIR/$mode_key.compile.stderr"
  node "$js_path" >"$ARTIFACT_DIR/$mode_key.stdout" 2>"$ARTIFACT_DIR/$mode_key.stderr"
  diff -u "$FIXTURE_DIR/expected.stdout" "$ARTIFACT_DIR/$mode_key.stdout"
  grep -q '^expr_macros_expanded=1$' "$ARTIFACT_DIR/$mode_key.compile.stdout"
  grep -q "^hxhx_macro_runtime_mode=$mode$" "$ARTIFACT_DIR/$mode_key.compile.stdout"
  echo "PROJECT_MACRO_MODULE_${mode_marker}:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"
}

expect_failure() {
  local label="$1"
  local mode="$2"
  local receipt="$3"
  local expected="$4"
  local out_dir="$WORK_DIR/negative-$label"
  mkdir -p "$out_dir"
  set +e
  HXHX_FORBID_STAGE0=1 \
  HAXE_BIN=__project_macro_negative_stage0_forbidden__ \
  HXHX_MACRO_RUNTIME_MODE="$mode" \
  HXHX_MACRO_HOST_AUTO_BUILD=0 \
  HXHX_MACRO_HOST_EXE="$MACRO_HOST_RESOLVED" \
  HXHX_NATIVE_MACRO_MODULE_RECEIPT="$receipt" \
  HXHX_CANDIDATE_COMMIT="$CANDIDATE_COMMIT" \
  HXHX_EXPR_MACROS="$EXPR" \
  "$HXHX_BIN_RESOLVED" \
    --hxhx-no-run \
    --js "$out_dir/main.js" \
    -cp "$FIXTURE_DIR/src" \
    -main Main \
    --hxhx-out "$out_dir" \
    >"$ARTIFACT_DIR/$label.stdout" \
    2>"$ARTIFACT_DIR/$label.stderr"
  local status="$?"
  set -e
  if [ "$status" -eq 0 ]; then
    echo "Expected project macro failure '$label' succeeded." >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$ARTIFACT_DIR/$label.stdout" "$ARTIFACT_DIR/$label.stderr"; then
    echo "Project macro failure '$label' did not contain: $expected" >&2
    cat "$ARTIFACT_DIR/$label.stdout" >&2
    cat "$ARTIFACT_DIR/$label.stderr" >&2
    exit 1
  fi
}

run_mode inproc
run_mode external-host

for mutation in wrong-candidate wrong-abi wrong-bytecode-digest wrong-expression missing-bytecode; do
  node "$ROOT/scripts/ci/native-macro-module-receipt.js" mutate-fixture \
    --report "$RECEIPT" \
    --out "$MODULE_ARTIFACT_DIR/fixture-$mutation.json" \
    --kind "$mutation" >/dev/null
done
expect_failure wrong_candidate inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-candidate.json" "candidate mismatch"
expect_failure wrong_abi inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-abi.json" "abiVersion mismatch"
expect_failure wrong_digest inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-bytecode-digest.json" "artifact SHA-256 mismatch"
expect_failure wrong_expression inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-expression.json" "registered expression mismatch"
expect_failure missing_artifact inproc "$MODULE_ARTIFACT_DIR/fixture-missing-bytecode.json" "artifact file not found"
expect_failure missing_receipt external-host "$WORK_DIR/does-not-exist.json" "file not found"
echo "PROJECT_MACRO_MODULE_NEGATIVE_PATHS:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

{
  echo "candidate_commit=$CANDIDATE_COMMIT"
  echo "hxhx_bin=$HXHX_BIN_RESOLVED"
  echo "macro_host=$MACRO_HOST_RESOLVED"
  echo "plugin_id=$PLUGIN_ID"
  echo "expression=$EXPR"
  echo "receipt=$RECEIPT"
} >"$ARTIFACT_DIR/meta.txt"

echo "PROJECT_MACRO_MODULE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"
