#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

TARGETS_RAW="${HXHX_GATE3_TARGETS:-}"
if [ "$#" -gt 0 ]; then
  TARGETS_RAW="$*"
fi

if [ -z "$TARGETS_RAW" ]; then
  echo "Usage:" >&2
  echo "  HXHX_GATE3_TARGETS=\"Macro,Js\" npm run test:upstream:runci-targets" >&2
  echo "  bash scripts/hxhx/run-upstream-runci-targets.sh Macro Js" >&2
  echo "" >&2
  echo "Notes:" >&2
  echo "  - Defaults upstream checkout to vendor/haxe (override with HAXE_UPSTREAM_DIR)." >&2
  echo "  - By default, missing target toolchains are treated as failures." >&2
  echo "    Set HXHX_GATE3_ALLOW_SKIP=1 to skip targets with missing deps." >&2
  exit 2
fi

UPSTREAM_DIR_ORIG="$UPSTREAM_DIR"
UPSTREAM_WORKTREE_DIR=""
WRAP_DIR=""

cleanup() {
  if [ -n "$WRAP_DIR" ] && [ -d "$WRAP_DIR" ]; then
    rm -rf "$WRAP_DIR" >/dev/null 2>&1 || true
  fi

  if [ -n "$UPSTREAM_WORKTREE_DIR" ] && [ -d "$UPSTREAM_WORKTREE_DIR" ]; then
    git -C "$UPSTREAM_DIR_ORIG" worktree remove --force "$UPSTREAM_WORKTREE_DIR" >/dev/null 2>&1 || true
    rm -rf "$UPSTREAM_WORKTREE_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

allow_skip="${HXHX_GATE3_ALLOW_SKIP:-0}"

die_or_skip() {
  local msg="$1"
  if [ "$allow_skip" = "1" ]; then
    echo "Skipping: $msg" >&2
    return 1
  fi
  echo "$msg" >&2
  exit 1
}

need_cmd() {
  local cmd="$1"
  local why="${2:-}"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$why" ]; then
    die_or_skip "Missing '$cmd' on PATH ($why)."
  else
    die_or_skip "Missing '$cmd' on PATH."
  fi
}

if [ ! -d "$UPSTREAM_DIR/tests/runci" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 3: missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

need_cmd "$HAXE_BIN" "stage0 compiler"
need_cmd "$HAXELIB_BIN" "haxelib CLI"

need_cmd dune "required to build stage1 hxhx"
need_cmd ocamlc "required to build stage1 hxhx"
need_cmd git "runci uses git clones for some targets"

# macOS runner patches upstream runci to skip sys tests; this requires python3.
if [ "$(uname -s)" = "Darwin" ] && [ "${HXHX_RUNCi_FORCE_SYS:-0}" != "1" ]; then
  need_cmd python3 "patch upstream runci to skip sys tests on macOS"
fi

# Resolve stage0 tool paths once so wrapper scripts don't depend on PATH ordering.
STAGE0_HAXE=""
STAGE0_HAXELIB=""
STAGE0_STD_PATH="${HAXE_STD_PATH:-}"

if [ -x "$HOME/haxe/versions/$UPSTREAM_REF/haxe" ]; then
  STAGE0_HAXE="$HOME/haxe/versions/$UPSTREAM_REF/haxe"
else
  STAGE0_HAXE="$(command -v "$HAXE_BIN")"
fi

if [ -x "$HOME/haxe/versions/$UPSTREAM_REF/haxelib" ]; then
  STAGE0_HAXELIB="$HOME/haxe/versions/$UPSTREAM_REF/haxelib"
else
  STAGE0_HAXELIB="$(command -v "$HAXELIB_BIN")"
fi

if [ -z "$STAGE0_STD_PATH" ]; then
  STAGE0_HAXE_DIR="$(cd "$(dirname "$STAGE0_HAXE")" && pwd)"
  if [ -d "$STAGE0_HAXE_DIR/std" ]; then
    STAGE0_STD_PATH="$STAGE0_HAXE_DIR/std"
  fi
fi

STAGE0_NEKOTOOLS="${NEKOTOOLS_BIN:-}"
STAGE0_NEKO="${NEKO_BIN:-}"

if [ -z "$STAGE0_NEKOTOOLS" ]; then
  if command -v nekotools >/dev/null 2>&1; then
    STAGE0_NEKOTOOLS="$(command -v nekotools)"
  elif [ -x "$HOME/haxe/neko/nekotools" ]; then
    STAGE0_NEKOTOOLS="$HOME/haxe/neko/nekotools"
  fi
fi
if [ -z "$STAGE0_NEKO" ]; then
  if command -v neko >/dev/null 2>&1; then
    STAGE0_NEKO="$(command -v neko)"
  elif [ -x "$HOME/haxe/neko/neko" ]; then
    STAGE0_NEKO="$HOME/haxe/neko/neko"
  fi
fi

if [ -z "$STAGE0_NEKOTOOLS" ] || [ ! -x "$STAGE0_NEKOTOOLS" ]; then
  echo "Skipping upstream Gate 3: nekotools not found (RunCi uses it for the echo server)." >&2
  echo "Install Neko tools (or set NEKOTOOLS_BIN=/path/to/nekotools)." >&2
  exit 0
fi

if [ -z "$STAGE0_NEKO" ] || [ ! -x "$STAGE0_NEKO" ]; then
  echo "Skipping upstream Gate 3: neko not found (some suites invoke it directly)." >&2
  echo "Install Neko (or set NEKO_BIN=/path/to/neko)." >&2
  exit 0
fi

NEKOPATH_DIR="$(cd "$(dirname "$STAGE0_NEKOTOOLS")" && pwd)"

# We want the upstream tests to match our compatibility target (default: 4.3.7).
if command -v git >/dev/null 2>&1 && git -C "$UPSTREAM_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  UPSTREAM_WORKTREE_DIR="$(mktemp -d)"
  if git -C "$UPSTREAM_DIR_ORIG" rev-parse --verify --quiet "$UPSTREAM_REF^{commit}" >/dev/null 2>&1; then
    git -C "$UPSTREAM_DIR_ORIG" worktree add --detach "$UPSTREAM_WORKTREE_DIR" "$UPSTREAM_REF" >/dev/null
    UPSTREAM_DIR="$UPSTREAM_WORKTREE_DIR"
  fi
else
  echo "Skipping upstream Gate 3: HAXE_UPSTREAM_DIR is not a git checkout (worktree is required to avoid modifying your upstream repo)." >&2
  exit 0
fi

patch_runci_skip_sys_on_macos() {
  if [ "${HXHX_RUNCi_FORCE_SYS:-0}" = "1" ]; then
    return 0
  fi
  if [ "$(uname -s)" != "Darwin" ]; then
    return 0
  fi

  local system_hx="$UPSTREAM_DIR/tests/runci/System.hx"
  [ -f "$system_hx" ] || return 0

  python3 - <<'PY'
import os
import sys

path = os.environ["UPSTREAM_DIR"] + "/tests/runci/System.hx"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

needle = "static public function runSysTest(cmd:String, ?args:Array<String>) {"
if needle not in src:
    sys.exit(0)

if "HXHX Gate runner" in src:
    # already patched
    sys.exit(0)

insert = (
    needle
    + "\n\t\t// HXHX Gate runner: upstream tests/sys contains unicode filename fixtures that are invalid on macOS/APFS.\n"
    + "\t\t// Skip sys tests on macOS to keep runci usable for other stages.\n"
    + "\t\t// Override with: HXHX_RUNCi_FORCE_SYS=1\n"
    + "\t\tif (Sys.systemName() == \"Mac\" && Sys.getEnv(\"HXHX_RUNCi_FORCE_SYS\") != \"1\") {\n"
    + "\t\t\tinfoMsg(\"Skipping sys tests on Mac (HXHX Gate runner; macOS/APFS unicode filename fixtures unsupported)\");\n"
    + "\t\t\treturn;\n"
    + "\t\t}\n"
)

src = src.replace(needle, insert)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
PY
}

preflight_target() {
  local t="$1"
  # Normalize: allow "Macro" or "macro".
  t="$(echo "$t" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    macro)
      need_cmd python3 "some macro/sys fixtures"
      need_cmd javac "some misc fixtures"
      if ! command -v cc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
        die_or_skip "Missing a C compiler on PATH (need cc/clang/gcc for some sys fixtures)."
      fi
      ;;
    js)
      need_cmd node "JavaScript target tests"
      ;;
    python)
      need_cmd python3 "Python target tests"
      ;;
    java|jvm)
      need_cmd javac "JVM/Java target tests"
      ;;
    neko)
      # already required at top
      ;;
    php)
      need_cmd php "PHP target tests"
      ;;
    lua)
      need_cmd lua "Lua target tests"
      ;;
    hl)
      need_cmd hl "HashLink target tests"
      ;;
    cs)
      # mono or dotnet depending on upstream; accept either.
      if ! command -v dotnet >/dev/null 2>&1 && ! command -v mono >/dev/null 2>&1; then
        die_or_skip "Missing dotnet/mono on PATH (C# target tests)."
      fi
      ;;
    cpp|cppia)
      if ! command -v g++ >/dev/null 2>&1 && ! command -v clang++ >/dev/null 2>&1; then
        die_or_skip "Missing a C++ compiler on PATH (C++/Cppia target tests)."
      fi
      ;;
    flash)
      die_or_skip "Flash target requires additional toolchain; not supported by this runner yet."
      ;;
    *)
      die_or_skip "Unknown runci target '$1'."
      ;;
  esac
}

# Build stage1 compiler (hxhx).
HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh" | tail -n 1)"
if [ -z "$HXHX_BIN" ] || [ ! -f "$HXHX_BIN" ]; then
  echo "Failed to build stage1 hxhx binary." >&2
  exit 1
fi

WRAP_DIR="$(mktemp -d)"

cat >"$WRAP_DIR/haxe" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export NEKOPATH="${NEKOPATH_DIR}"
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
export HAXE_BIN="${STAGE0_HAXE}"
exec "${HXHX_BIN}" "\$@"
EOF
chmod +x "$WRAP_DIR/haxe"

cat >"$WRAP_DIR/haxelib" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export NEKOPATH="${NEKOPATH_DIR}"
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
exec "${STAGE0_HAXELIB}" "\$@"
EOF
chmod +x "$WRAP_DIR/haxelib"

cat >"$WRAP_DIR/nekotools" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export NEKOPATH="${NEKOPATH_DIR}"
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
exec "${STAGE0_NEKOTOOLS}" "\$@"
EOF
chmod +x "$WRAP_DIR/nekotools"

cat >"$WRAP_DIR/neko" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export NEKOPATH="${NEKOPATH_DIR}"
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
exec "${STAGE0_NEKO}" "\$@"
EOF
chmod +x "$WRAP_DIR/neko"

targets=()
for tok in $TARGETS_RAW; do
  # Split comma lists passed as a single arg/env var.
  IFS=',' read -r -a parts <<<"$tok"
  for p in "${parts[@]}"; do
    p="$(echo "$p" | tr -d '[:space:]')"
    [ -z "$p" ] && continue
    targets+=("$p")
  done
done

echo "== Gate 3: upstream tests/runci targets (${targets[*]}) (via hxhx stage0 shim)"

(
  cd "$UPSTREAM_DIR/tests"
  if [ ! -d ".haxelib" ]; then
    PATH="$WRAP_DIR:$PATH" haxelib newrepo >/dev/null
  fi
  export UPSTREAM_DIR
  patch_runci_skip_sys_on_macos
)

failures=0
summary=()

for target in "${targets[@]}"; do
  echo ""
  echo "== Target: $target"

  if ! preflight_target "$target"; then
    summary+=("$target: SKIP (missing deps)")
    continue
  fi

  start="$(date +%s)"
  set +e
  (
    cd "$UPSTREAM_DIR/tests"
    if [ -n "${STAGE0_STD_PATH:-}" ]; then
      export HAXE_STD_PATH="${STAGE0_STD_PATH}"
    fi
    TEST="$target" PATH="$WRAP_DIR:$PATH" "$STAGE0_HAXE" RunCi.hxml
  )
  code="$?"
  set -e
  end="$(date +%s)"
  dt="$((end - start))"

  if [ "$code" -eq 0 ]; then
    summary+=("$target: PASS (${dt}s)")
  else
    summary+=("$target: FAIL (${dt}s, exit $code)")
    failures=1
    if [ "${HXHX_GATE3_FAIL_FAST:-0}" = "1" ]; then
      break
    fi
  fi
done

echo ""
echo "== Gate 3 summary"
for line in "${summary[@]}"; do
  echo "$line"
done

exit "$failures"
