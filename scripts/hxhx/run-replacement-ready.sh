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
    echo "  HAXE_UPSTREAM_DIR=/path/to/haxe     (default: $ROOT/vendor/haxe)" >&2
    exit 2
    ;;
esac

FAIL_FAST="${HXHX_M7_FAIL_FAST:-0}"
KEEP_LOGS="${HXHX_M7_KEEP_LOGS:-0}"
DRY_RUN="${HXHX_M7_DRY_RUN:-0}"
STRICT="${HXHX_M7_STRICT:-}"

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

UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$ROOT/vendor/haxe}"
HOST_OS="$(uname -s)"
if [ "$HOST_OS" = "Darwin" ]; then
  M7_GATE3_TARGETS_DEFAULT="Macro,Neko"
else
  M7_GATE3_TARGETS_DEFAULT="Macro,Js,Neko"
fi
GATE3_TARGETS="${HXHX_GATE3_TARGETS:-$M7_GATE3_TARGETS_DEFAULT}"

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command on PATH: $cmd" >&2
    return 1
  fi
  return 0
}

if [ "$PROFILE" = "full" ] && [ "$STRICT" = "1" ]; then
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

run_check() {
  local name="$1"
  local cmd="$2"
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
    bash -lc "$cmd" 2>&1 | tee "$log_file"
    code="${PIPESTATUS[0]}"
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
  else
    if [ "$STRICT" = "1" ] && [ "$skipped" = "1" ]; then
      summary+=("$name: FAIL (${elapsed}s, skipped in strict mode)")
    else
      summary+=("$name: FAIL (${elapsed}s, exit=$code)")
    fi
    failures=1
    if [ "$FAIL_FAST" = "1" ]; then
      return "$code"
    fi
  fi

  return 0
}

add_checks_fast() {
  run_check "ci:guards" "cd '$ROOT' && npm run -s ci:guards"
  run_check "hxhx-targets" "cd '$ROOT' && npm run -s test:hxhx-targets"
  run_check "gate2-display" "cd '$ROOT' && npm run -s test:upstream:runci-macro-stage3-display"
  run_check "builtin-target-smoke" "cd '$ROOT' && npm run -s test:hxhx:builtin-target-smoke"
}

add_checks_full() {
  add_checks_fast
  run_check "gate1-unit-macro" "cd '$ROOT' && npm run -s test:upstream:unit-macro"
  run_check "gate2-runci-macro" "cd '$ROOT' && npm run -s test:upstream:runci-macro"
  run_check "gate3-runci-targets" "cd '$ROOT' && HXHX_GATE3_TARGETS='${GATE3_TARGETS}' npm run -s test:upstream:runci-targets"
}

echo "== HXHX replacement-ready bundle"
echo "profile=$PROFILE strict=$STRICT fail_fast=$FAIL_FAST dry_run=$DRY_RUN"
echo "upstream_dir=$UPSTREAM_DIR"
echo "gate3_targets=$GATE3_TARGETS"
if [ "$HOST_OS" = "Darwin" ] && [ -z "${HXHX_GATE3_TARGETS:-}" ]; then
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
  exit 1
fi
