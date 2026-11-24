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
# Later steps compile five more fixtures the same way and compare each program with upstream:
# project-macro-reification (quoted syntax), project-macro-constant-args (String, Int, Float, and
# Bool parameters, an inferred result), expr_macro_pass_driver/suite (the upstream unit-suite
# TestMain shape), project-macro-context (haxe.macro.Context services and Context.error), and
# project-macro-define (Context.defineModule and Context.defineType).
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

# Without any -cp, the macro class beside Main.hx is found on the implicit working-directory
# classpath and still runs.
(
  cd "$FIXTURE_DIR/src"
  HXHX_FORBID_STAGE0=1 HAXE_BIN=__project_macro_cwd_stage0_forbidden__ \
    "$HXHX_BIN_RESOLVED" --hxhx-stage3 --hxhx-no-run -main Main --hxhx-out "$WORK_DIR/app-cwd" --hxhx-macro-cache "$CACHE_DIR"
) >"$ARTIFACT_DIR/cwd.compile.stdout" 2>"$ARTIFACT_DIR/cwd.compile.stderr"
require_line cwd '^expr_macros_expanded=1$'
run_app cwd
echo "PROJECT_MACRO_MODULE_IMPLICIT_CLASSPATH:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

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

# Fill directory $1 with links to only the tools the missing-toolchain step runs, so a PATH of that
# directory hides dune and ocamlopt even where the OCaml toolchain is installed in /usr/bin (apt on
# Linux). The step's shell needs bash, mkdir, dirname, basename, grep, and cat. hxhx starts each
# tool through /bin/sh with a watcher that calls sleep, and setsid where it exists
# (hxhx.macro.ProjectMacroPluginProcess). A missing optional tool is skipped.
make_toolless_bin() {
  local dir="$1"
  local tool
  local tool_path
  mkdir -p "$dir"
  for tool in sh bash mkdir dirname basename grep cat sleep setsid; do
    tool_path="$(command -v "$tool" 2>/dev/null || true)"
    case "$tool_path" in
      /*) ln -sf "$tool_path" "$dir/$tool" ;;
    esac
  done
}

# Without dune and ocamlopt on PATH the plugin cannot be built; the call fails with one clear reason.
TOOLLESS_BIN="$WORK_DIR/toolless-bin"
make_toolless_bin "$TOOLLESS_BIN"
(
  PATH="$TOOLLESS_BIN"
  export PATH
  if command -v dune >/dev/null 2>&1 || command -v ocamlopt >/dev/null 2>&1; then
    echo "The missing-toolchain check still finds dune or ocamlopt on PATH=$PATH." >&2
    exit 1
  fi
  expect_failure missing_toolchain "$FIXTURE_DIR/src" Main \
    "expression macro $DECLARATION was not executed: the project macro plugin is unavailable: project macros need \`dune\` and the OCaml native compiler (\`ocamlopt\`) on PATH" \
    --hxhx-macro-cache "$WORK_DIR/toolless-cache"
)
echo "PROJECT_MACRO_MODULE_MISSING_TOOLCHAIN:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# The external host cannot dispatch declarations yet, so a selected call fails instead of running.
expect_failure external_host "$FIXTURE_DIR/src" Main \
  "expression macro $DECLARATION was not executed: the external macro host has no structured dispatch method for project macro declarations yet" \
  --hxhx-macro-runtime external-host --hxhx-macro-cache "$CACHE_DIR"
require_line external_host '^hxhx_macro_runtime_mode=external-host$'
echo "PROJECT_MACRO_MODULE_EXTERNAL_HOST_REJECTED:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# The receipt check validates only the artifact this hxhx loads. hxhx picks it by its own executable
# (hxhx.macro.InProcMacroRuntime.pluginArtifactKind): a bytecode compiler (`.bc`, `.byte`) loads the
# `.cma` (`artifacts.bytecode`), a native one the `.cmxs` (`artifacts.native`). The digest mutation
# below changes that artifact's digest and requires hxhx to report its mismatch, so a wrong choice
# here fails the step instead of passing it.
case "$(printf '%s' "$HXHX_BIN_RESOLVED" | tr '[:upper:]' '[:lower:]')" in
  *.bc | *.byte) LOADED_ARTIFACT_KIND=bytecode ;;
  *) LOADED_ARTIFACT_KIND=native ;;
esac

# A changed receipt is rejected; hxhx rebuilds instead of loading the plugin it names.
mutate_receipt() {
  node -e '
const fs = require("fs")
const [path, kind, artifactKind] = process.argv.slice(1)
const receipt = JSON.parse(fs.readFileSync(path, "utf8"))
if (kind === "compiler") receipt.compilerIdentity = "another-compiler"
else if (kind === "abi") receipt.abiVersion = 1
else if (kind === "declaration") receipt.declarations = ["Identity.missing"]
else if (kind === "digest") receipt.artifacts[artifactKind].sha256 = "0".repeat(64)
else throw new Error("unknown mutation " + kind)
fs.writeFileSync(path, JSON.stringify(receipt, null, 2) + "\n")
' "$RECEIPT" "$1" "$LOADED_ARTIFACT_KIND"
}
for mutation in "compiler:compilerIdentity" "abi:abiVersion" "declaration:registered" "digest:artifact SHA-256 mismatch"; do
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

# A macro whose body is written with reification (`macro { ... }`, `$v{}`, `$b{}`, `$a{}`, `$e{}`,
# field splices, `@:pos`) builds as a plugin and the program prints what upstream prints.
REIFICATION_DIR="$ROOT/test/fixtures/project-macro-reification"
(
  cd "$REIFICATION_DIR"
  haxe oracle.hxml
) >"$ARTIFACT_DIR/reification.oracle.stdout" 2>"$ARTIFACT_DIR/reification.oracle.stderr"
diff -u "$REIFICATION_DIR/expected.stdout" "$ARTIFACT_DIR/reification.oracle.stdout"
compile_app reification "$REIFICATION_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
require_line reification '^project_macro_plugin=built$'
require_line reification '^expr_macros_expanded=1$'
"$WORK_DIR/app-reification/out.exe" >"$ARTIFACT_DIR/reification.stdout" 2>"$ARTIFACT_DIR/reification.stderr"
diff -u "$REIFICATION_DIR/expected.stdout" "$ARTIFACT_DIR/reification.stdout"
echo "PROJECT_MACRO_MODULE_REIFICATION:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Macros whose parameters are constants receive the values the call wrote, as in upstream Haxe 4.3.7:
# `String`, `Int`, `Float`, and `Bool` parameters, and a result left to inference.
CONSTANT_DIR="$ROOT/test/fixtures/project-macro-constant-args"
(
  cd "$CONSTANT_DIR"
  haxe oracle.hxml
) >"$ARTIFACT_DIR/constant_args.oracle.stdout" 2>"$ARTIFACT_DIR/constant_args.oracle.stderr"
diff -u "$CONSTANT_DIR/expected.stdout" "$ARTIFACT_DIR/constant_args.oracle.stdout"
compile_app constant_args "$CONSTANT_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
require_line constant_args '^project_macro_plugin=built$'
require_line constant_args '^expr_macros_expanded=4$'
"$WORK_DIR/app-constant_args/out.exe" >"$ARTIFACT_DIR/constant_args.stdout" 2>"$ARTIFACT_DIR/constant_args.stderr"
diff -u "$CONSTANT_DIR/expected.stdout" "$ARTIFACT_DIR/constant_args.stdout"

# The upstream unit-suite shape (`tests/unit` TestMain): a module-level main calls String-parameter
# macros as a `for` iterable and as a statement; the program prints what upstream prints.
SUITE_DIR="$ROOT/test/fixtures/expr_macro_pass_driver"
(
  cd "$SUITE_DIR"
  haxe -cp . -main suite.SuiteMain --interp
) >"$ARTIFACT_DIR/suite.oracle.stdout" 2>"$ARTIFACT_DIR/suite.oracle.stderr"
printf 'specs\nissues:suite.issues\n' | diff -u - "$ARTIFACT_DIR/suite.oracle.stdout"
compile_app suite "$SUITE_DIR" suite.SuiteMain --hxhx-macro-cache "$CACHE_DIR"
require_line suite '^expr_macros_expanded=2$'
"$WORK_DIR/app-suite/out.exe" >"$ARTIFACT_DIR/suite.stdout" 2>"$ARTIFACT_DIR/suite.stderr"
diff -u "$ARTIFACT_DIR/suite.oracle.stdout" "$ARTIFACT_DIR/suite.stdout"
echo "PROJECT_MACRO_MODULE_CONSTANT_ARGUMENTS:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# A macro that uses the first haxe.macro.Context services (positions, defines, parse, error) through
# the compiler's host service prints what upstream prints, and Context.error reports its message
# at its position exactly as upstream does.
CONTEXT_DIR="$ROOT/test/fixtures/project-macro-context"
(
  cd "$CONTEXT_DIR"
  haxe oracle.hxml
) >"$ARTIFACT_DIR/context.oracle.stdout" 2>"$ARTIFACT_DIR/context.oracle.stderr"
diff -u "$CONTEXT_DIR/expected.stdout" "$ARTIFACT_DIR/context.oracle.stdout"
set +e
(
  cd "$CONTEXT_DIR"
  haxe oracle-error.hxml
) >"$ARTIFACT_DIR/context_error.oracle.stdout" 2>"$ARTIFACT_DIR/context_error.oracle.stderr"
set -e
diff -u "$CONTEXT_DIR/expected-error.stderr" "$ARTIFACT_DIR/context_error.oracle.stderr"
compile_app context "$CONTEXT_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR" -D probe_flag -D probe_dashed -D probe_value=forty-two
require_line context '^expr_macros_expanded=3$'
"$WORK_DIR/app-context/out.exe" >"$ARTIFACT_DIR/context.stdout" 2>"$ARTIFACT_DIR/context.stderr"
diff -u "$CONTEXT_DIR/expected.stdout" "$ARTIFACT_DIR/context.stdout"
expect_failure context_error "$CONTEXT_DIR/src" ErrorMain "src/ErrorMain.hx:4: characters 36-40 : context error here" \
  --hxhx-macro-cache "$CACHE_DIR"
diff -u "$CONTEXT_DIR/expected-error.stderr" "$ARTIFACT_DIR/context_error.compile.stderr"
echo "PROJECT_MACRO_MODULE_CONTEXT:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

# Macros that define modules (Context.defineModule, Context.defineType) in the shape of upstream's
# UnitBuilder: the compile types the defined classes and the program prints what upstream prints.
DEFINE_DIR="$ROOT/test/fixtures/project-macro-define"
(
  cd "$DEFINE_DIR"
  haxe oracle.hxml
) >"$ARTIFACT_DIR/define.oracle.stdout" 2>"$ARTIFACT_DIR/define.oracle.stderr"
diff -u "$DEFINE_DIR/expected.stdout" "$ARTIFACT_DIR/define.oracle.stdout"
compile_app define "$DEFINE_DIR/src" Main --hxhx-macro-cache "$CACHE_DIR"
require_line define '^expr_macros_expanded=2$'
"$WORK_DIR/app-define/out.exe" >"$ARTIFACT_DIR/define.stdout" 2>"$ARTIFACT_DIR/define.stderr"
diff -u "$DEFINE_DIR/expected.stdout" "$ARTIFACT_DIR/define.stdout"
echo "PROJECT_MACRO_MODULE_DEFINE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"

{
  echo "candidate_commit=$CANDIDATE_COMMIT"
  echo "hxhx_bin=$HXHX_BIN_RESOLVED"
  echo "hxhx_md5=$(node -e 'process.stdout.write(require("crypto").createHash("md5").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$HXHX_BIN_RESOLVED")"
  echo "macro_host=$MACRO_HOST_RESOLVED"
  echo "declarations=$DECLARATION"
  echo "loaded_artifact_kind=$LOADED_ARTIFACT_KIND"
  echo "receipt=$RECEIPT"
  echo "cold_compile_ms=$cold_ms"
  echo "warm_compile_ms=$warm_ms"
} >"$ARTIFACT_DIR/meta.txt"

echo "PROJECT_MACRO_MODULE:PASS" | tee -a "$ARTIFACT_DIR/markers.txt"
