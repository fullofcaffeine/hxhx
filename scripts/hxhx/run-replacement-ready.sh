#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PROFILE="${HXHX_M7_PROFILE:-fast}"
if [ "$#" -gt 0 ]; then
  PROFILE="$1"
fi

case "$PROFILE" in
  fast|full) ;;
  *)
    echo "Usage: bash scripts/hxhx/run-replacement-ready.sh [fast|full]" >&2
    echo "Env:" >&2
    echo "  HXHX_M7_PROFILE=fast|full" >&2
    echo "  HXHX_M7_FAIL_FAST=0|1               (default 0)" >&2
    echo "  HXHX_M7_STRICT=0|1                  (default: full=1, fast=0)" >&2
    echo "  HXHX_M7_KEEP_LOGS=0|1               (default 0)" >&2
    echo "  HXHX_M7_DRY_RUN=0|1                 (default 0)" >&2
    echo "  HXHX_M7_SCOPE_FILE=<json>           (default: strict=docs/02-user-guide/compat/native-scope-targets.json, otherwise docs/02-user-guide/compat/scoped-1.0-targets.json)" >&2
    echo "  HXHX_M7_REQUIRE_PLUGIN_MATRIX=0|1   (default: strict full=1, otherwise 0)" >&2
    echo "  HXHX_M7_SHARED_ARTIFACT_DIR=<dir>   (default: .artifacts/gate-m7-shared)" >&2
    echo "  HAXE_UPSTREAM_DIR=/path/to/haxe     (default: $ROOT/vendor/haxe)" >&2
    exit 2
    ;;
esac

FAIL_FAST="${HXHX_M7_FAIL_FAST:-0}"
KEEP_LOGS="${HXHX_M7_KEEP_LOGS:-0}"
DRY_RUN="${HXHX_M7_DRY_RUN:-0}"
STRICT="${HXHX_M7_STRICT:-}"
REQUIRE_PLUGIN_MATRIX_RAW="${HXHX_M7_REQUIRE_PLUGIN_MATRIX:-}"
REQUIRE_PLUGIN_MATRIX="0"

for v in FAIL_FAST KEEP_LOGS DRY_RUN; do
  eval "value=\${$v}"
  case "$value" in
    0|1) ;;
    *) echo "Invalid $v=$value (expected 0 or 1)." >&2; exit 2 ;;
  esac
done

if [ -z "$STRICT" ]; then
  if [ "$PROFILE" = "full" ]; then
    STRICT=1
  else
    STRICT=0
  fi
fi
case "$STRICT" in
  0|1) ;;
  *) echo "Invalid HXHX_M7_STRICT=$STRICT (expected 0 or 1)." >&2; exit 2 ;;
esac

if [ "$STRICT" = "1" ]; then
  DEFAULT_SCOPE_FILE="$ROOT/docs/02-user-guide/compat/native-scope-targets.json"
else
  DEFAULT_SCOPE_FILE="$ROOT/docs/02-user-guide/compat/scoped-1.0-targets.json"
fi
SCOPE_FILE="${HXHX_M7_SCOPE_FILE:-$DEFAULT_SCOPE_FILE}"

if [ -n "$REQUIRE_PLUGIN_MATRIX_RAW" ]; then
  REQUIRE_PLUGIN_MATRIX="$REQUIRE_PLUGIN_MATRIX_RAW"
elif [ "$PROFILE" = "full" ] && [ "$STRICT" = "1" ]; then
  REQUIRE_PLUGIN_MATRIX="1"
fi
case "$REQUIRE_PLUGIN_MATRIX" in
  0|1) ;;
  *) echo "Invalid HXHX_M7_REQUIRE_PLUGIN_MATRIX=$REQUIRE_PLUGIN_MATRIX (expected 0 or 1)." >&2; exit 2 ;;
esac

UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$ROOT/vendor/haxe}"
HOST_OS="$(uname -s)"
M7_GATE3_TARGETS_DEFAULT=""
SHARED_ARTIFACT_TOOL="$ROOT/scripts/ci/m7-shared-artifacts.js"
SHARED_ARTIFACT_DIR="${HXHX_M7_SHARED_ARTIFACT_DIR:-$ROOT/.artifacts/gate-m7-shared}"
SHARED_ARTIFACT_RECEIPT="$SHARED_ARTIFACT_DIR/receipt.json"
SHARED_ARTIFACTS_READY=0

load_scope_targets() {
  local scope_file="$1"
  if [ ! -f "$scope_file" ]; then
    return 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    return 1
  fi

  node -e '
const fs = require("fs");
const filePath = process.argv[1];
const doc = JSON.parse(fs.readFileSync(filePath, "utf8"));
if (!Array.isArray(doc.gate3Targets) || doc.gate3Targets.length === 0) {
  process.exit(2);
}
process.stdout.write(doc.gate3Targets.join(","));
' "$scope_file"
}

if [ -z "${HXHX_GATE3_TARGETS:-}" ]; then
  if ! M7_GATE3_TARGETS_DEFAULT="$(load_scope_targets "$SCOPE_FILE" 2>/dev/null)"; then
    if [ "$HOST_OS" = "Darwin" ]; then
      M7_GATE3_TARGETS_DEFAULT="Macro,Neko"
    else
      M7_GATE3_TARGETS_DEFAULT="Macro,Js,Neko"
    fi
  fi
  GATE3_TARGETS="$M7_GATE3_TARGETS_DEFAULT"
else
  GATE3_TARGETS="${HXHX_GATE3_TARGETS}"
fi

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command on PATH: $cmd" >&2
    return 1
  fi
  return 0
}

if [ "$PROFILE" = "full" ] && [ "$STRICT" = "1" ] && [ "$DRY_RUN" != "1" ]; then
  if [ ! -d "$UPSTREAM_DIR/tests/runci" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
    echo "Full M7 strict mode requires upstream checkout at '$UPSTREAM_DIR'." >&2
    echo "Run: bash scripts/vendor/fetch-haxe-upstream.sh" >&2
    exit 1
  fi

  missing=0
  for cmd in dune ocamlc git haxe haxelib python3 javac node neko pypy3; do
    if ! need_cmd "$cmd"; then
      missing=1
    fi
  done
  if ! command -v cc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
    echo "Missing C compiler (need one of: cc, clang, gcc)." >&2
    missing=1
  fi
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
fi

summary=()
failures=0

prepare_shared_strict_artifacts() {
  local start end elapsed
  local built_hxhx=""
  local built_macro_host=""
  local built_macro_host_runtime=""
  local shared_macro_host_runtime=""
  local code=0

  if [ "$STRICT" != "1" ]; then
    return 0
  fi

  echo ""
  echo "== M7 preparation: shared stage0-free native artifacts"
  if [ "$DRY_RUN" = "1" ]; then
    summary+=("shared-native-artifacts: DRY_RUN (0s)")
    echo "M7_SHARED_ARTIFACTS:DRY_RUN"
    return 0
  fi

  start="$(date +%s)"
  rm -rf "$SHARED_ARTIFACT_DIR"
  mkdir -p "$SHARED_ARTIFACT_DIR"
  export HXHX_BOOTSTRAP_PREFER_NATIVE=1

  set +e
  built_hxhx="$(
    HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used \
      bash "$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1
  )"
  code="$?"
  set -e
  if [ "$code" -ne 0 ] || [ -z "$built_hxhx" ] || [ ! -x "$built_hxhx" ] || [[ "$built_hxhx" != *.exe ]]; then
    end="$(date +%s)"
    elapsed="$((end - start))"
    summary+=("shared-native-artifacts: FAIL (${elapsed}s, hxhx build exit=$code)")
    echo "M7 shared preparation did not produce a native hxhx executable." >&2
    echo "M7_SHARED_ARTIFACTS:FAIL"
    return 1
  fi

  set +e
  built_macro_host="$(
    HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used \
      bash "$ROOT/scripts/hxhx/build-hxhx-macro-host.sh" | tail -n 1
  )"
  code="$?"
  set -e
  if [ "$code" -ne 0 ] || [ -z "$built_macro_host" ] || [ ! -x "$built_macro_host" ] || [[ "$built_macro_host" != *.exe ]]; then
    end="$(date +%s)"
    elapsed="$((end - start))"
    summary+=("shared-native-artifacts: FAIL (${elapsed}s, macro-host build exit=$code)")
    echo "M7 shared preparation did not produce a native macro-host executable." >&2
    echo "M7_SHARED_ARTIFACTS:FAIL"
    return 1
  fi

  built_macro_host_runtime="$(dirname "$built_macro_host")/runtime/.hx_runtime.objs/byte"
  if [ ! -d "$built_macro_host_runtime" ] || [ ! -f "$built_macro_host_runtime/hxHxMacroModuleHost.cmi" ]; then
    end="$(date +%s)"
    elapsed="$((end - start))"
    summary+=("shared-native-artifacts: FAIL (${elapsed}s, macro-host runtime interfaces missing)")
    echo "M7 shared preparation did not find the macro-host runtime interface files." >&2
    echo "M7_SHARED_ARTIFACTS:FAIL"
    return 1
  fi

  HXHX_BIN="$SHARED_ARTIFACT_DIR/hxhx.exe"
  HXHX_MACRO_HOST_EXE="$SHARED_ARTIFACT_DIR/hxhx-macro-host.exe"
  shared_macro_host_runtime="$SHARED_ARTIFACT_DIR/runtime/.hx_runtime.objs/byte"
  cp "$built_hxhx" "$HXHX_BIN"
  cp "$built_macro_host" "$HXHX_MACRO_HOST_EXE"
  mkdir -p "$(dirname "$shared_macro_host_runtime")"
  cp -R "$built_macro_host_runtime" "$shared_macro_host_runtime"
  chmod +x "$HXHX_BIN" "$HXHX_MACRO_HOST_EXE"
  export HXHX_BIN HXHX_MACRO_HOST_EXE

  if ! node "$SHARED_ARTIFACT_TOOL" write \
    --root "$ROOT" \
    --report "$SHARED_ARTIFACT_RECEIPT" \
    --hxhx-bin "$HXHX_BIN" \
    --macro-host-bin "$HXHX_MACRO_HOST_EXE" \
    --macro-host-runtime "$shared_macro_host_runtime"; then
    end="$(date +%s)"
    elapsed="$((end - start))"
    summary+=("shared-native-artifacts: FAIL (${elapsed}s, receipt validation)")
    echo "M7_SHARED_ARTIFACTS:FAIL"
    return 1
  fi

  SHARED_ARTIFACTS_READY=1
  end="$(date +%s)"
  elapsed="$((end - start))"
  summary+=("shared-native-artifacts: PASS (${elapsed}s)")
  echo "m7_shared_hxhx=$HXHX_BIN"
  echo "m7_shared_macro_host=$HXHX_MACRO_HOST_EXE"
  echo "m7_shared_macro_host_runtime=$shared_macro_host_runtime"
  echo "m7_shared_receipt=$SHARED_ARTIFACT_RECEIPT"
}

validate_shared_strict_artifacts() {
  if [ "$STRICT" != "1" ] || [ "$DRY_RUN" = "1" ]; then
    return 0
  fi
  if [ "$SHARED_ARTIFACTS_READY" != "1" ]; then
    echo "M7 shared artifacts were not prepared." >&2
    return 1
  fi
  node "$SHARED_ARTIFACT_TOOL" validate \
    --root "$ROOT" \
    --report "$SHARED_ARTIFACT_RECEIPT" \
    --expected-commit "$(git -C "$ROOT" rev-parse HEAD)" \
    --quiet
}

run_check() {
  local name="$1"
  local cmd="$2"
  local marker="$3"
  local log_file=""
  local code=0
  local start end elapsed
  local skipped=0

  echo ""
  echo "== M7 check: $name"
  echo "== command: $cmd"

  start="$(date +%s)"

  if [ "$DRY_RUN" = "1" ]; then
    code=0
  else
    log_file="$(mktemp -t hxhx-m7-${name//[^a-zA-Z0-9]/_}.XXXXXX.log)"
    set +e
    if ! validate_shared_strict_artifacts; then
      echo "M7 shared artifact validation failed before '$name'." | tee "$log_file" >&2
      code=4
    else
      bash -lc "$cmd" 2>&1 | tee "$log_file"
      code="${PIPESTATUS[0]}"
      if [ "$code" -eq 0 ] && ! validate_shared_strict_artifacts; then
        echo "M7 shared artifact validation failed after '$name'." | tee -a "$log_file" >&2
        code=4
      fi
    fi
    set -e

    if grep -Eq "Skipping upstream Gate|Skipping upstream|SKIP \(missing deps\)" "$log_file"; then
      skipped=1
    fi

    if [ "$KEEP_LOGS" = "1" ]; then
      echo "== log retained: $log_file"
    else
      rm -f "$log_file"
    fi
  fi

  end="$(date +%s)"
  elapsed="$((end - start))"

  if [ "$STRICT" = "1" ] && [ "$skipped" = "1" ]; then
    code=3
  fi

  if [ "$code" -eq 0 ]; then
    summary+=("$name: PASS (${elapsed}s)")
    echo "${marker}:PASS"
  else
    if [ "$STRICT" = "1" ] && [ "$skipped" = "1" ]; then
      summary+=("$name: FAIL (${elapsed}s, skipped in strict mode)")
    else
      summary+=("$name: FAIL (${elapsed}s, exit=$code)")
    fi
    echo "${marker}:FAIL"
    failures=1
    if [ "$FAIL_FAST" = "1" ]; then
      return "$code"
    fi
  fi

  return 0
}

add_checks_fast() {
  run_check "ci:guards" "cd '$ROOT' && npm run -s ci:guards" "CI_GUARDS"
  if [ "$STRICT" = "1" ]; then
    run_check "stage0-policy-release" "cd '$ROOT' && npm run -s test:stage0-policy:release" "STAGE0_POLICY_RELEASE"
    run_check "gate2-display" "cd '$ROOT' && npm run -s test:upstream:runci-macro-stage3-display" "GATE2_DISPLAY"
    run_check \
      "builtin-target-smoke (strict lanes)" \
      "cd '$ROOT' && HXHX_BUILTIN_SMOKE_OCAML=0 HXHX_BUILTIN_SMOKE_JS_NATIVE=1 HXHX_BUILTIN_SMOKE_REQUIRE_JS_NATIVE=1 npm run -s test:hxhx:builtin-target-smoke" \
      "BUILTIN_TARGET_SMOKE"
  else
    run_check "hxhx-targets" "cd '$ROOT' && npm run -s test:hxhx-targets" "HXHX_TARGETS"
    run_check "gate2-display" "cd '$ROOT' && npm run -s test:upstream:runci-macro-stage3-display" "GATE2_DISPLAY"
    run_check "builtin-target-smoke" "cd '$ROOT' && npm run -s test:hxhx:builtin-target-smoke" "BUILTIN_TARGET_SMOKE"
  fi
}

add_checks_full() {
  add_checks_fast
  run_check "gate1-unit-macro" "cd '$ROOT' && npm run -s test:upstream:unit-macro" "GATE1_MACRO"
  run_check "gate2-runci-macro" "cd '$ROOT' && npm run -s test:upstream:runci-macro" "GATE2_MACRO"
  run_check "gate3-runci-targets" "cd '$ROOT' && HXHX_GATE3_TARGETS='${GATE3_TARGETS}' npm run -s test:upstream:runci-targets" "GATE3_TARGETS"
  if [ "$REQUIRE_PLUGIN_MATRIX" = "1" ]; then
    run_check "plugin-matrix" "cd '$ROOT' && npm run -s test:plugins:strict-matrix" "PLUGIN_MATRIX"
  fi
}

echo "== HXHX replacement-ready bundle"
echo "profile=$PROFILE strict=$STRICT fail_fast=$FAIL_FAST dry_run=$DRY_RUN"
echo "upstream_dir=$UPSTREAM_DIR"
echo "scope_file=$SCOPE_FILE"
echo "gate3_targets=$GATE3_TARGETS"
echo "require_plugin_matrix=$REQUIRE_PLUGIN_MATRIX"
if [ "$STRICT" = "1" ]; then
  export HXHX_FORBID_STAGE0=1
  echo "strict_stage0=enabled (HXHX_FORBID_STAGE0=1)"
fi
if ! prepare_shared_strict_artifacts; then
  echo ""
  echo "== M7 summary"
  for line in "${summary[@]}"; do
    echo "$line"
  done
  if [ "$STRICT" = "1" ]; then
    echo "M7_STRICT_STAGE0:FAIL"
  fi
  echo "M7_REPLACEMENT_READY:FAIL"
  exit 1
fi
if [ "$HOST_OS" = "Darwin" ] && [ -z "${HXHX_GATE3_TARGETS:-}" ] && [ ! -f "$SCOPE_FILE" ]; then
  echo "note: using Darwin default Gate3 target set (Macro,Neko). Set HXHX_GATE3_TARGETS to override."
fi

if [ "$PROFILE" = "full" ]; then
  add_checks_full
else
  add_checks_fast
fi

echo ""
echo "== M7 summary"
for line in "${summary[@]}"; do
  echo "$line"
done

if [ "$failures" -ne 0 ]; then
  if [ "$STRICT" = "1" ]; then
    echo "M7_STRICT_STAGE0:FAIL"
  fi
  echo "M7_REPLACEMENT_READY:FAIL"
  exit 1
fi

if [ "$STRICT" = "1" ]; then
  echo "M7_STRICT_STAGE0:PASS"
fi
echo "M7_REPLACEMENT_READY:PASS"
