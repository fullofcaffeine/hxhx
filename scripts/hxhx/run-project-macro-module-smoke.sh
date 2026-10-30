#!/usr/bin/env bash
set -euo pipefail

# Build a real project expression macro into a native plugin with hxhx's own Stage3 OCaml
# emitter, load it in-process, and check that the compiled program behaves like upstream Haxe.
#
# Fixture: test/fixtures/project-macro-identity. The plugin registers the macro declaration
# `Identity.preserve` (plugin ABI version 2). The external macro host loads the same plugin but
# has no structured dispatch method yet, so there the call must be reported as unexecuted.
#
# The hxhx binary must contain the current compiler sources. Until the committed bootstrap
# snapshot includes this plugin ABI, pass HXHX_BIN and HXHX_MACRO_HOST_EXE built from source.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$ROOT/test/fixtures/project-macro-identity"
ARTIFACT_DIR="${HXHX_PROJECT_MACRO_ARTIFACT_DIR:-$ROOT/.artifacts/project-macro-module}"
CANDIDATE_COMMIT="${HXHX_CANDIDATE_COMMIT:-}"
DECLARATION='Identity.preserve'
PLUGIN_ID='hxhx.project-macro.fixture'
PLUGIN_ENTRY='hxhxmacrohost.MacroDeclarationPlugin'
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
  --hxhx-no-run \
  -cp "$ROOT/packages/hxhx-core/src" \
  -cp "$FIXTURE_DIR/src" \
  -main "$PLUGIN_ENTRY" \
  --hxhx-out "$PLUGIN_OUT" \
  -D ocaml_dune_layout=plugin \
  -D "ocaml_plugin_register_macro=$PLUGIN_ID" \
  -D "ocaml_plugin_macro_declarations=$DECLARATION" \
  >"$ARTIFACT_DIR/plugin-generate.stdout" \
  2>"$ARTIFACT_DIR/plugin-generate.stderr"

# The compiler reports the plugin library's bytecode archive; the native one sits beside it.
PLUGIN_LIBRARY="$(basename "$(sed -n 's/^exe=//p' "$ARTIFACT_DIR/plugin-generate.stdout")" .cma)"
if [ -z "$PLUGIN_LIBRARY" ]; then
  echo "Project macro plugin generation did not report its library artifact." >&2
  exit 1
fi
(
  cd "$PLUGIN_OUT"
  dune build "./$PLUGIN_LIBRARY.cma" "./$PLUGIN_LIBRARY.cmxs"
) >"$ARTIFACT_DIR/plugin-build.stdout" 2>"$ARTIFACT_DIR/plugin-build.stderr"

GENERATED_BYTECODE_PLUGIN="$PLUGIN_OUT/_build/default/$PLUGIN_LIBRARY.cma"
GENERATED_NATIVE_PLUGIN="$PLUGIN_OUT/_build/default/$PLUGIN_LIBRARY.cmxs"
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
  --declarations "$DECLARATION" \
  --native-artifact "$NATIVE_PLUGIN" \
  --bytecode-artifact "$BYTECODE_PLUGIN" \
  >"$ARTIFACT_DIR/receipt-write.stdout"
node "$ROOT/scripts/ci/native-macro-module-receipt.js" validate \
  --report "$RECEIPT" \
  --expected-candidate "$CANDIDATE_COMMIT" \
  >"$ARTIFACT_DIR/receipt-summary.json"
echo "PROJECT_MACRO_MODULE_BUILD:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Compile one fixture entry point with the selected macro runtime and receipt.
# Arguments: label, macro mode, receipt path, main class, extra hxhx arguments...
compile_app() {
  local label="$1"
  local mode="$2"
  local receipt="$3"
  local main="$4"
  shift 4
  local out_dir="$WORK_DIR/app-$label"
  mkdir -p "$out_dir"
  HXHX_FORBID_STAGE0=1 \
  HAXE_BIN=__project_macro_app_stage0_forbidden__ \
  HXHX_MACRO_RUNTIME_MODE="$mode" \
  HXHX_MACRO_HOST_AUTO_BUILD=0 \
  HXHX_MACRO_HOST_EXE="$MACRO_HOST_RESOLVED" \
  HXHX_NATIVE_MACRO_MODULE_RECEIPT="$receipt" \
  HXHX_CANDIDATE_COMMIT="$CANDIDATE_COMMIT" \
  "$HXHX_BIN_RESOLVED" \
    --hxhx-stage3 \
    --hxhx-no-run \
    -cp "$FIXTURE_DIR/src" \
    -main "$main" \
    --hxhx-out "$out_dir" \
    "$@" \
    >"$ARTIFACT_DIR/$label.compile.stdout" \
    2>"$ARTIFACT_DIR/$label.compile.stderr"
}

# In-process: the plugin runs the macro body, and the native program matches upstream.
compile_app inproc inproc "$RECEIPT" Main
grep -q '^hxhx_macro_runtime_mode=inproc$' "$ARTIFACT_DIR/inproc.compile.stdout"
grep -q '^expr_macros_expanded=1$' "$ARTIFACT_DIR/inproc.compile.stdout"
if grep -q '^expr_macro_unexecuted' "$ARTIFACT_DIR/inproc.compile.stdout"; then
  echo "In-process compile left the selected macro unexecuted." >&2
  exit 1
fi
"$WORK_DIR/app-inproc/out.exe" >"$ARTIFACT_DIR/inproc.stdout" 2>"$ARTIFACT_DIR/inproc.stderr"
diff -u "$FIXTURE_DIR/expected.stdout" "$ARTIFACT_DIR/inproc.stdout"
echo "PROJECT_MACRO_MODULE_INPROC:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

expect_failure() {
  local label="$1"
  local mode="$2"
  local receipt="$3"
  local main="$4"
  local expected="$5"
  set +e
  compile_app "$label" "$mode" "$receipt" "$main" --hxhx-no-emit
  local status="$?"
  set -e
  if [ "$status" -eq 0 ]; then
    echo "Expected project macro failure '$label' succeeded." >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$ARTIFACT_DIR/$label.compile.stdout" "$ARTIFACT_DIR/$label.compile.stderr"; then
    echo "Project macro failure '$label' did not contain: $expected" >&2
    cat "$ARTIFACT_DIR/$label.compile.stdout" >&2
    cat "$ARTIFACT_DIR/$label.compile.stderr" >&2
    exit 1
  fi
}

# Report an unexecuted selected macro without failing the type-only compile.
expect_unexecuted() {
  local label="$1"
  local mode="$2"
  local receipt="$3"
  local reason="$4"
  compile_app "$label" "$mode" "$receipt" Main --hxhx-no-emit
  grep -q '^expr_macros_unexecuted=1$' "$ARTIFACT_DIR/$label.compile.stdout"
  if ! grep -q "^expr_macro_unexecuted\[0\]=.*$DECLARATION: .*$reason" "$ARTIFACT_DIR/$label.compile.stdout"; then
    echo "Project macro run '$label' did not report the unexecuted declaration ($reason)." >&2
    cat "$ARTIFACT_DIR/$label.compile.stdout" >&2
    exit 1
  fi
}

# The macro's own exception becomes a compile error at the call; it is never an ordinary call.
expect_failure wrong_signature inproc "$RECEIPT" WrongSignature "expression macro $DECLARATION: the macro failed: Identity.preserve: parameter name changed"
echo "PROJECT_MACRO_MODULE_MACRO_FAILURE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Without a plugin, the selected declaration keeps the explicit unexecuted report.
expect_unexecuted no_plugin inproc "" "no loaded project macro plugin provides declaration $DECLARATION"
echo "PROJECT_MACRO_MODULE_UNEXECUTED_WITHOUT_PLUGIN:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# The external host validates and loads the same plugin but cannot dispatch declarations yet.
expect_unexecuted external_host external-host "$RECEIPT" "external macro host protocol has no structured dispatch method"
grep -q '^hxhx_macro_runtime_mode=external-host$' "$ARTIFACT_DIR/external_host.compile.stdout"
echo "PROJECT_MACRO_MODULE_EXTERNAL_HOST_UNEXECUTED:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

for mutation in wrong-candidate wrong-abi old-abi wrong-bytecode-digest wrong-declaration missing-bytecode; do
  node "$ROOT/scripts/ci/native-macro-module-receipt.js" mutate-fixture \
    --report "$RECEIPT" \
    --out "$MODULE_ARTIFACT_DIR/fixture-$mutation.json" \
    --kind "$mutation" >/dev/null
done
expect_failure wrong_candidate inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-candidate.json" Main "candidate mismatch"
expect_failure wrong_abi inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-abi.json" Main "abiVersion mismatch"
expect_failure old_abi inproc "$MODULE_ARTIFACT_DIR/fixture-old-abi.json" Main "abiVersion mismatch: expected 2, got 1"
expect_failure wrong_digest inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-bytecode-digest.json" Main "artifact SHA-256 mismatch"
expect_failure wrong_declaration inproc "$MODULE_ARTIFACT_DIR/fixture-wrong-declaration.json" Main "registered declaration mismatch"
expect_failure missing_artifact inproc "$MODULE_ARTIFACT_DIR/fixture-missing-bytecode.json" Main "artifact file not found"
expect_failure missing_receipt external-host "$WORK_DIR/does-not-exist.json" Main "file not found"
echo "PROJECT_MACRO_MODULE_NEGATIVE_PATHS:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

{
  echo "candidate_commit=$CANDIDATE_COMMIT"
  echo "hxhx_bin=$HXHX_BIN_RESOLVED"
  echo "macro_host=$MACRO_HOST_RESOLVED"
  echo "plugin_id=$PLUGIN_ID"
  echo "declarations=$DECLARATION"
  echo "receipt=$RECEIPT"
} >"$ARTIFACT_DIR/meta.txt"

echo "PROJECT_MACRO_MODULE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"
