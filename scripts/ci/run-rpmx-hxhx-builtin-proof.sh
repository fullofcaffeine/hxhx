#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FETCH_SCRIPT="$ROOT/scripts/vendor/fetch-reflaxe-elixir-upstream.sh"
OCAMLOPT_WRAPPER="$ROOT/scripts/hxhx/ocamlopt-with-threads.sh"

RUN_ID="${RPMX_HXHX_BUILTIN_RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"
ARTIFACT_DIR="${RPMX_HXHX_BUILTIN_ARTIFACT_DIR:-$ROOT/.artifacts/rpmx/hxhx-builtin/$RUN_ID}"
WORK_DIR="${RPMX_HXHX_BUILTIN_WORK_DIR:-$ROOT/.tmp/rpmx-hxhx-builtin-proof}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "rpmx hxhx builtin proof: missing required command: $1" >&2
    exit 2
  fi
}

resolve_source_repo() {
  if [ -n "${REFLAXE_ELIXIR_DIR:-}" ]; then
    if [ ! -d "$REFLAXE_ELIXIR_DIR/.git" ]; then
      echo "rpmx hxhx builtin proof: REFLAXE_ELIXIR_DIR is not a git repo: $REFLAXE_ELIXIR_DIR" >&2
      exit 2
    fi
    printf '%s\n' "$REFLAXE_ELIXIR_DIR"
    return
  fi
  if [ -d "$ROOT/vendor/reflaxe-elixir/.git" ]; then
    printf '%s\n' "$ROOT/vendor/reflaxe-elixir"
    return
  fi
  if [ ! -x "$FETCH_SCRIPT" ]; then
    echo "rpmx hxhx builtin proof: missing fetch script: $FETCH_SCRIPT" >&2
    exit 2
  fi
  local fetch_output
  fetch_output="$(bash "$FETCH_SCRIPT")"
  printf '%s\n' "$fetch_output" >&2
  printf '%s\n' "$fetch_output" | awk -F= '/^reflaxe_elixir_dir=/{print $2}' | tail -n1
}

resolve_hxhx_bin() {
  if [ -n "${HXHX_BIN:-}" ]; then
    printf '%s\n' "$HXHX_BIN"
    return
  fi
  HXHX_FORBID_STAGE0=1 HXHX_FORCE_STAGE0=0 bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1
}

require_cmd git
require_cmd node
require_cmd ocamlopt
require_cmd haxe

if [ -z "${OCAMLOPT:-}" ] && [ -x "$OCAMLOPT_WRAPPER" ]; then
  export OCAMLOPT="$OCAMLOPT_WRAPPER"
fi

source_repo="$(resolve_source_repo)"
source_commit="$(git -C "$source_repo" rev-parse HEAD)"
for rel in src vendor/reflaxe/src vendor/phoenix_shared/src; do
  if [ ! -d "$source_repo/$rel" ]; then
    echo "rpmx hxhx builtin proof: missing source path: $source_repo/$rel" >&2
    exit 2
  fi
done
if [ ! -f "$source_repo/src/Run.hx" ]; then
  echo "rpmx hxhx builtin proof: missing Reflaxe.elixir Run.hx entrypoint" >&2
  exit 2
fi

hxhx_bin="$(resolve_hxhx_bin)"
if [ ! -x "$hxhx_bin" ] && [[ "$hxhx_bin" != *.bc ]]; then
  echo "rpmx hxhx builtin proof: failed to resolve executable hxhx binary: $hxhx_bin" >&2
  exit 2
fi
if [[ "$hxhx_bin" == *.bc ]]; then
  hxhx_cmd=(ocamlrun "$hxhx_bin")
  hxhx_mode="bytecode"
else
  hxhx_cmd=("$hxhx_bin")
  hxhx_mode="native"
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$ARTIFACT_DIR"
out_dir="$WORK_DIR/out"
stdout_log="$ARTIFACT_DIR/compile.stdout.log"
stderr_log="$ARTIFACT_DIR/compile.stderr.log"

set +e
HXHX_FORBID_STAGE0=1 "${hxhx_cmd[@]}" \
  --ocaml \
  --hxhx-emit-full-bodies \
  --hxhx-no-run \
  -cp "$source_repo/src" \
  -cp "$source_repo/vendor/reflaxe/src" \
  -cp "$source_repo/vendor/phoenix_shared/src" \
  -main Run \
  --hxhx-out "$out_dir" \
  >"$stdout_log" 2>"$stderr_log"
compile_code="$?"
set -e

cat "$stdout_log"
if [ "$compile_code" -ne 0 ]; then
  cat "$stderr_log" >&2
  echo "rpmx hxhx builtin proof: compile failed with exit $compile_code" >&2
  exit "$compile_code"
fi

grep -q '^stage3=ok$' "$stdout_log"
built_exe="$out_dir/out.exe"
if [ ! -x "$built_exe" ]; then
  echo "rpmx hxhx builtin proof: missing built executable: $built_exe" >&2
  exit 1
fi

exe_copy="$ARTIFACT_DIR/out.exe"
cp "$built_exe" "$exe_copy"
exe_sha256="$(shasum -a 256 "$exe_copy" | awk '{print $1}')"
printf '%s  out.exe\n' "$exe_sha256" >"$ARTIFACT_DIR/out.exe.sha256"

summary="$ARTIFACT_DIR/rpmx-hxhx-builtin.summary.json"
node - "$summary" "$source_repo" "$source_commit" "$hxhx_bin" "$hxhx_mode" "$out_dir" "$exe_copy" "$exe_sha256" "$stdout_log" "$stderr_log" <<'NODE'
const fs = require('fs')
const [summaryPath, sourceRepo, sourceCommit, hxhxBin, hxhxMode, outDir, exePath, exeSha256, stdoutLog, stderrLog] = process.argv.slice(2)
fs.writeFileSync(summaryPath, JSON.stringify({
  workload: 'reflaxe-elixir-compiler-run-entrypoint',
  proof: {
    host: 'hxhx',
    mode: 'native-stage3-ocaml-built-in-reflaxe.ocaml',
    hxhxBin,
    hxhxMode,
    sourceRepo,
    sourceCommit,
    main: 'Run',
    classpaths: [
      'src',
      'vendor/reflaxe/src',
      'vendor/phoenix_shared/src',
    ],
    outDir,
    builtExecutable: exePath,
    builtExecutableSha256: exeSha256,
    stdoutLog,
    stderrLog,
  },
  result: 'RPMX_HXHX_BUILTIN:PASS',
}, null, 2) + '\n')
NODE

echo "rpmx_hxhx_builtin_artifact_dir=$ARTIFACT_DIR"
echo "rpmx_hxhx_builtin_summary=$summary"
echo "rpmx_hxhx_builtin_source_repo=$source_repo"
echo "rpmx_hxhx_builtin_source_commit=$source_commit"
echo "rpmx_hxhx_builtin_hxhx_bin=$hxhx_bin"
echo "rpmx_hxhx_builtin_out_exe_sha256=$exe_sha256"
echo "RPMX_HXHX_BUILTIN:PASS"
