#!/usr/bin/env bash
set -euo pipefail

# Compile a project that calls a real expression macro with a plain hxhx command, and check that
# hxhx builds, caches, rebuilds, and validates the macro's native plugin by itself.
#
# Fixture: test/fixtures/project-macro-identity. `Main.hx` calls `Identity.preserve(...)`. hxhx
# finds the call, builds a plugin from `Identity.hx` with its own Stage3 OCaml emitter and dune,
# writes a receipt into its plugin cache, loads the plugin in-process, and runs the macro. The
# native program must print what upstream Haxe 4.3.7 prints.
#
# The hxhx binary must contain the current compiler sources. Until the committed bootstrap
# snapshot includes the plugin build driver, pass HXHX_BIN (and HXHX_MACRO_HOST_EXE) built from
# source; see docs/01-getting-started/TESTING.md.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$ROOT/test/fixtures/project-macro-identity"
ARTIFACT_DIR="${HXHX_PROJECT_MACRO_ARTIFACT_DIR:-$ROOT/.artifacts/project-macro-module}"
CANDIDATE_COMMIT="${HXHX_CANDIDATE_COMMIT:-}"
DECLARATION='Identity.preserve'
TMP_ROOT="$ROOT/.tmp"
mkdir -p "$TMP_ROOT"
WORK_DIR="$(mktemp -d "$TMP_ROOT/project-macro-module.XXXXXX")"
CACHE_DIR="$WORK_DIR/macro-cache"

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
rm -rf "${ARTIFACT_DIR:?}"/*
cd "$ROOT"

for tool in dune ocamlopt node haxe; do
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

now_ms() {
  node -e 'process.stdout.write(String(Date.now()))'
}

ORACLE_STDOUT="$ARTIFACT_DIR/oracle.stdout"
(
  cd "$FIXTURE_DIR"
  haxe oracle.hxml
) >"$ORACLE_STDOUT" 2>"$ARTIFACT_DIR/oracle.stderr"
diff -u "$FIXTURE_DIR/expected.stdout" "$ORACLE_STDOUT"
echo "PROJECT_MACRO_MODULE_ORACLE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Compile one entry point of a fixture source directory from its parent directory, the way a
# user would. Arguments: label, source directory, main class, extra hxhx arguments...
compile_app() {
  local label="$1"
  local src_dir="$2"
  local main="$3"
  shift 3
  local out_dir="$WORK_DIR/app-$label"
  mkdir -p "$out_dir"
  (
    cd "$(dirname "$src_dir")"
    HXHX_FORBID_STAGE0=1 \
    HAXE_BIN=__project_macro_app_stage0_forbidden__ \
    HXHX_MACRO_HOST_AUTO_BUILD=0 \
    HXHX_MACRO_HOST_EXE="$MACRO_HOST_RESOLVED" \
    "$HXHX_BIN_RESOLVED" \
      --hxhx-stage3 \
      --hxhx-no-run \
      -cp "$(basename "$src_dir")" \
      -main "$main" \
      --hxhx-out "$out_dir" \
      "$@"
  ) >"$ARTIFACT_DIR/$label.compile.stdout" 2>"$ARTIFACT_DIR/$label.compile.stderr"
}

require_line() {
  local label="$1"
  local pattern="$2"
  if ! grep -Eq "$pattern" "$ARTIFACT_DIR/$label.compile.stdout"; then
    echo "Project macro run '$label' did not print a line matching: $pattern" >&2
    cat "$ARTIFACT_DIR/$label.compile.stdout" >&2
    cat "$ARTIFACT_DIR/$label.compile.stderr" >&2
    exit 1
  fi
}

run_app() {
  local label="$1"
  "$WORK_DIR/app-$label/out.exe" >"$ARTIFACT_DIR/$label.stdout" 2>"$ARTIFACT_DIR/$label.stderr"
  diff -u "$FIXTURE_DIR/expected.stdout" "$ARTIFACT_DIR/$label.stdout"
}

expect_failure() {
  local label="$1"
  local src_dir="$2"
  local main="$3"
  local expected="$4"
  shift 4
  set +e
  compile_app "$label" "$src_dir" "$main" --hxhx-no-emit "$@"
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

# A selected call that cannot run is reported, with its reason, and the type-only compile goes on.
expect_unexecuted() {
  local label="$1"
  local reason="$2"
  shift 2
  compile_app "$label" "$FIXTURE_DIR/src" Main --hxhx-no-emit "$@"
  require_line "$label" '^expr_macros_unexecuted=1$'
  if ! grep -Fq "$DECLARATION: " "$ARTIFACT_DIR/$label.compile.stdout" || ! grep -Fq "$reason" "$ARTIFACT_DIR/$label.compile.stdout"; then
    echo "Project macro run '$label' did not report the unexecuted declaration ($reason)." >&2
    cat "$ARTIFACT_DIR/$label.compile.stdout" >&2
    exit 1
  fi
}

# Cold: hxhx builds the plugin, runs the macro, and the native program matches upstream.
cold_start="$(now_ms)"
compile_app cold "$FIXTURE_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
cold_ms="$(($(now_ms) - cold_start))"
require_line cold '^hxhx_macro_runtime_mode=inproc$'
require_line cold '^project_macro_plugin=built$'
require_line cold '^expr_macros_expanded=1$'
if grep -q '^expr_macro_unexecuted' "$ARTIFACT_DIR/cold.compile.stdout"; then
  echo "The cold compile left the selected macro unexecuted." >&2
  cat "$ARTIFACT_DIR/cold.compile.stdout" >&2
  exit 1
fi
RECEIPT="$(sed -n 's/^project_macro_plugin_receipt=//p' "$ARTIFACT_DIR/cold.compile.stdout")"
[ -f "$RECEIPT" ] || {
  echo "The cold compile did not report its plugin receipt." >&2
  exit 1
}
echo "PROJECT_MACRO_MODULE_BUILD:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"
run_app cold
echo "PROJECT_MACRO_MODULE_INPROC:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Warm: the same inputs reuse the cached plugin.
warm_start="$(now_ms)"
compile_app warm "$FIXTURE_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
warm_ms="$(($(now_ms) - warm_start))"
require_line warm '^project_macro_plugin=reused$'
require_line warm '^expr_macros_expanded=1$'
run_app warm
echo "PROJECT_MACRO_MODULE_CACHE_HIT:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Keep the validated plugin beside a copy of its receipt for the Full1 evidence summary.
MODULE_ARTIFACT_DIR="$ARTIFACT_DIR/module"
mkdir -p "$MODULE_ARTIFACT_DIR"
cp "$RECEIPT" "$MODULE_ARTIFACT_DIR/project-macro-receipt.json"
for artifact_path in $(node -e 'const r = require(process.argv[1]); console.log(r.artifacts.native.path, r.artifacts.bytecode.path)' "$RECEIPT"); do
  mkdir -p "$MODULE_ARTIFACT_DIR/$(dirname "$artifact_path")"
  cp "$(dirname "$RECEIPT")/$artifact_path" "$MODULE_ARTIFACT_DIR/$artifact_path"
done

# The macro's own exception becomes a compile error at the call; it is never an ordinary call.
expect_failure wrong_signature "$FIXTURE_DIR/src" WrongSignature \
  "expression macro $DECLARATION: the macro failed: Identity.preserve: parameter name changed" --hxhx-macro-cache "$CACHE_DIR"
echo "PROJECT_MACRO_MODULE_MACRO_FAILURE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Editing the macro class rebuilds the plugin; an unchanged class reuses it.
EDIT_DIR="$WORK_DIR/edited"
mkdir -p "$EDIT_DIR"
cp -R "$FIXTURE_DIR/src" "$EDIT_DIR/src"
compile_app edited "$EDIT_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
require_line edited '^project_macro_plugin=built$'
compile_app edited_again "$EDIT_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
require_line edited_again '^project_macro_plugin=reused$'
printf '\n// edited by the project macro smoke\n' >>"$EDIT_DIR/src/Identity.hx"
compile_app edited_twice "$EDIT_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
require_line edited_twice '^project_macro_plugin=built$'
require_line edited_twice '^project_macro_plugin_reason=.*macro source changed since the plugin was built'
run_app edited_twice
echo "PROJECT_MACRO_MODULE_REBUILD_ON_EDIT:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Without dune and ocamlopt on PATH the plugin cannot be built; the call reports one clear reason.
(
  PATH="/usr/bin:/bin"
  export PATH
  if command -v dune >/dev/null 2>&1 || command -v ocamlopt >/dev/null 2>&1; then
    echo "The missing-toolchain check needs a PATH without dune and ocamlopt; /usr/bin or /bin provides one." >&2
    exit 1
  fi
  expect_unexecuted missing_toolchain "project macros need \`dune\` and the OCaml native compiler (\`ocamlopt\`) on PATH" \
    --hxhx-macro-cache "$WORK_DIR/toolless-cache"
)
echo "PROJECT_MACRO_MODULE_MISSING_TOOLCHAIN:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# The external host cannot dispatch declarations yet, so it never builds or loads the plugin.
expect_unexecuted external_host "the external macro host has no structured dispatch method for project macro declarations yet" \
  --hxhx-macro-runtime external-host --hxhx-macro-cache "$CACHE_DIR"
require_line external_host '^hxhx_macro_runtime_mode=external-host$'
echo "PROJECT_MACRO_MODULE_EXTERNAL_HOST_UNEXECUTED:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# A changed receipt is rejected; hxhx rebuilds instead of loading the plugin it names.
mutate_receipt() {
  node -e '
const fs = require("fs")
const [path, kind] = process.argv.slice(1)
const receipt = JSON.parse(fs.readFileSync(path, "utf8"))
if (kind === "compiler") receipt.compilerIdentity = "another-compiler"
else if (kind === "abi") receipt.abiVersion = 1
else if (kind === "declaration") receipt.declarations = ["Identity.missing"]
else if (kind === "digest") receipt.artifacts.native.sha256 = "0".repeat(64)
else throw new Error("unknown mutation " + kind)
fs.writeFileSync(path, JSON.stringify(receipt, null, 2) + "\n")
' "$RECEIPT" "$1"
}
for mutation in compiler:compilerIdentity abi:abiVersion declaration:registered digest:SHA-256; do
  kind="${mutation%%:*}"
  expected="${mutation#*:}"
  mutate_receipt "$kind"
  compile_app "receipt_$kind" "$FIXTURE_DIR/src" Main --hxhx-no-emit --hxhx-macro-cache "$CACHE_DIR"
  require_line "receipt_$kind" '^project_macro_plugin=built$'
  require_line "receipt_$kind" "^project_macro_plugin_reason=native macro module receipt: .*$expected"
  require_line "receipt_$kind" '^expr_macros_expanded=1$'
done
echo "PROJECT_MACRO_MODULE_NEGATIVE_PATHS:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# The plain command a user types: the default cache directory and no plugin settings.
(
  cd "$FIXTURE_DIR"
  HXHX_FORBID_STAGE0=1 HAXE_BIN=__project_macro_plain_stage0_forbidden__ \
    "$HXHX_BIN_RESOLVED" --hxhx-stage3 --hxhx-no-run -cp src -main Main --hxhx-out "$WORK_DIR/app-plain"
) >"$ARTIFACT_DIR/plain.compile.stdout" 2>"$ARTIFACT_DIR/plain.compile.stderr"
require_line plain '^expr_macros_expanded=1$'
run_app plain
echo "PROJECT_MACRO_MODULE_PLAIN_COMMAND:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

{
  echo "candidate_commit=$CANDIDATE_COMMIT"
  echo "hxhx_bin=$HXHX_BIN_RESOLVED"
  echo "hxhx_md5=$(node -e 'process.stdout.write(require("crypto").createHash("md5").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$HXHX_BIN_RESOLVED")"
  echo "macro_host=$MACRO_HOST_RESOLVED"
  echo "declarations=$DECLARATION"
  echo "receipt=$RECEIPT"
  echo "cold_compile_ms=$cold_ms"
  echo "warm_compile_ms=$warm_ms"
} >"$ARTIFACT_DIR/meta.txt"

echo "PROJECT_MACRO_MODULE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"
