#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

# The upstream `tests/party` stage is network-heavy (clones + `haxelib install`) and tends
# to be the flakiest part of the suite across local environments. We default to skipping it.
#
# This env var is consumed by a small patch applied to upstream `tests/runci/targets/Macro.hx`.
#
# Override:
# - set `HXHX_GATE2_SKIP_PARTY=0` to enable party tests
: "${HXHX_GATE2_SKIP_PARTY:=1}"
export HXHX_GATE2_SKIP_PARTY

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
  echo "    Macro defaults to non-delegating direct mode (HXHX_GATE3_MACRO_MODE=direct)." >&2
  echo "    Set HXHX_GATE3_MACRO_MODE=stage0_shim to use the historical stage0 RunCi harness path for Macro." >&2
  echo "    Retry defaults: HXHX_GATE3_RETRY_COUNT=1, HXHX_GATE3_RETRY_TARGETS=Js, HXHX_GATE3_RETRY_DELAY_SEC=3" >&2
  echo "    Long-run observability: HXHX_GATE3_TARGET_HEARTBEAT_SEC=20 (set 0 to disable)." >&2
  echo "    Optional per-target timeout: HXHX_GATE3_TARGET_TIMEOUT_SEC=0 (disabled by default)." >&2
  echo "    Set HXHX_GATE3_RETRY_COUNT=0 to disable retries." >&2
  echo "    On macOS, Js server async timeouts are relaxed by default (HXHX_GATE3_JS_SERVER_TIMEOUT_MS=60000)." >&2
  echo "    Set HXHX_GATE3_FORCE_JS_SERVER=1 to run without timeout patches (debug mode)." >&2
  echo "    Python runs default to no-install mode (HXHX_GATE3_PYTHON_ALLOW_INSTALL=0); require both python3 and pypy3." >&2
  echo "    Set HXHX_GATE3_PYTHON_ALLOW_INSTALL=1 to allow upstream installer/network fallback." >&2
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
macro_mode="${HXHX_GATE3_MACRO_MODE:-direct}"
case "$macro_mode" in
  stage0_shim|direct) ;;
  *)
    echo "Unknown HXHX_GATE3_MACRO_MODE: $macro_mode (expected stage0_shim or direct)." >&2
    exit 2
    ;;
esac

python_allow_install_raw="${HXHX_GATE3_PYTHON_ALLOW_INSTALL:-0}"
case "$python_allow_install_raw" in
  0|1)
    ;;
  *)
    echo "Invalid HXHX_GATE3_PYTHON_ALLOW_INSTALL: $python_allow_install_raw (expected 0 or 1)." >&2
    exit 2
    ;;
esac
python_allow_install="$python_allow_install_raw"

retry_count_raw="${HXHX_GATE3_RETRY_COUNT:-1}"
case "$retry_count_raw" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_GATE3_RETRY_COUNT: $retry_count_raw (expected non-negative integer)." >&2
    exit 2
    ;;
esac
retry_count="$retry_count_raw"

retry_delay_raw="${HXHX_GATE3_RETRY_DELAY_SEC:-3}"
case "$retry_delay_raw" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_GATE3_RETRY_DELAY_SEC: $retry_delay_raw (expected non-negative integer)." >&2
    exit 2
    ;;
esac
retry_delay_sec="$retry_delay_raw"

retry_targets_raw="${HXHX_GATE3_RETRY_TARGETS:-Js}"
retry_targets_normalized="$(echo "$retry_targets_raw" | tr ',' ' ')"

js_server_timeout_raw="${HXHX_GATE3_JS_SERVER_TIMEOUT_MS:-60000}"
case "$js_server_timeout_raw" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_GATE3_JS_SERVER_TIMEOUT_MS: $js_server_timeout_raw (expected non-negative integer)." >&2
    exit 2
    ;;
esac
js_server_timeout_ms="$js_server_timeout_raw"
export HXHX_GATE3_JS_SERVER_TIMEOUT_MS="$js_server_timeout_ms"

target_heartbeat_raw="${HXHX_GATE3_TARGET_HEARTBEAT_SEC:-20}"
case "$target_heartbeat_raw" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_GATE3_TARGET_HEARTBEAT_SEC: $target_heartbeat_raw (expected non-negative integer)." >&2
    exit 2
    ;;
esac
target_heartbeat_sec="$target_heartbeat_raw"

target_timeout_raw="${HXHX_GATE3_TARGET_TIMEOUT_SEC:-0}"
case "$target_timeout_raw" in
  ''|*[!0-9]*)
    echo "Invalid HXHX_GATE3_TARGET_TIMEOUT_SEC: $target_timeout_raw (expected non-negative integer)." >&2
    exit 2
    ;;
esac
target_timeout_sec="$target_timeout_raw"

should_retry_target() {
  local target_lower="$1"
  local token=""
  for token in $retry_targets_normalized; do
    token="$(echo "$token" | tr '[:upper:]' '[:lower:]')"
    if [ -n "$token" ] && [ "$token" = "$target_lower" ]; then
      return 0
    fi
  done
  return 1
}

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

resolve_lua_bin() {
  if command -v lua >/dev/null 2>&1; then
    command -v lua
    return 0
  fi
  if command -v lua5.4 >/dev/null 2>&1; then
    command -v lua5.4
    return 0
  fi
  if command -v lua5.3 >/dev/null 2>&1; then
    command -v lua5.3
    return 0
  fi
  return 1
}

probe_haxelib_binary() {
  local bin="$1"
  "$bin" help >/dev/null 2>&1 || "$bin" --help >/dev/null 2>&1 || "$bin" version >/dev/null 2>&1
}

resolve_runnable_haxelib() {
  local requested="$1"
  local candidate=""
  local resolved=""
  local -a candidates=()
  local -a probes=()

  # Prefer the pinned native stage0 toolchain first for deterministic CI behavior.
  probes+=("$HOME/haxe/versions/$UPSTREAM_REF/haxelib")
  probes+=("$HOME/haxe/versions/stable/haxelib")

  if [ -n "$requested" ]; then
    probes+=("$requested")
  fi
  probes+=("haxelib")
  probes+=("$ROOT/node_modules/.bin/haxelib")

  for candidate in "${probes[@]}"; do
    if [ -z "$candidate" ]; then
      continue
    fi
    if [[ "$candidate" == */* ]]; then
      resolved="$candidate"
    else
      resolved="$(command -v "$candidate" 2>/dev/null || true)"
    fi
    if [ -z "$resolved" ] || [ ! -x "$resolved" ]; then
      continue
    fi
    if ! probe_haxelib_binary "$resolved"; then
      echo "Rejected non-runnable haxelib candidate: $resolved" >&2
      continue
    fi
    candidates+=("$resolved")
  done

  for candidate in "${candidates[@]}"; do
    echo "$candidate"
    return 0
  done

  return 1
}

if [ ! -d "$UPSTREAM_DIR/tests/runci" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 3: missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  if command -v haxelib >/dev/null 2>&1; then
    HAXELIB_BIN="haxelib"
  else
    echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
    exit 1
  fi
fi

need_cmd "$HAXE_BIN" "stage0 compiler"

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

#
# Prefer a runnable `haxelib` (validated with a smoke command), not just an executable path.
STAGE0_HAXELIB="$(resolve_runnable_haxelib "$HAXELIB_BIN" || true)"
if [ -z "$STAGE0_HAXELIB" ]; then
  echo "Missing runnable haxelib binary (requested '$HAXELIB_BIN')." >&2
  exit 1
fi
echo "Using stage0 haxelib: ${STAGE0_HAXELIB}" >&2

if [ -z "$STAGE0_STD_PATH" ]; then
  STAGE0_HAXE_DIR="$(cd "$(dirname "$STAGE0_HAXE")" && pwd)"
  if [ -d "$STAGE0_HAXE_DIR/std" ]; then
    STAGE0_STD_PATH="$STAGE0_HAXE_DIR/std"
  fi
fi

STAGE0_NEKOTOOLS="${NEKOTOOLS_BIN:-}"
STAGE0_NEKO="${NEKO_BIN:-}"
LUA_BIN="${LUA_BIN:-}"

if [ -z "$STAGE0_NEKOTOOLS" ]; then
  if [ -x "$HOME/haxe/neko/nekotools" ]; then
    STAGE0_NEKOTOOLS="$HOME/haxe/neko/nekotools"
  elif [ -x "$HOME/haxe/neko/versions/$UPSTREAM_REF/nekotools" ]; then
    STAGE0_NEKOTOOLS="$HOME/haxe/neko/versions/$UPSTREAM_REF/nekotools"
  elif command -v nekotools >/dev/null 2>&1; then
    STAGE0_NEKOTOOLS="$(command -v nekotools)"
  fi
fi
if [ -z "$STAGE0_NEKO" ]; then
  if [ -x "$HOME/haxe/neko/neko" ]; then
    STAGE0_NEKO="$HOME/haxe/neko/neko"
  elif [ -x "$HOME/haxe/neko/versions/$UPSTREAM_REF/neko" ]; then
    STAGE0_NEKO="$HOME/haxe/neko/versions/$UPSTREAM_REF/neko"
  elif command -v neko >/dev/null 2>&1; then
    STAGE0_NEKO="$(command -v neko)"
  fi
fi

if [ -z "$LUA_BIN" ]; then
  LUA_BIN="$(resolve_lua_bin || true)"
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

dir_has_std_ndll() {
  local candidate="${1:-}"
  [ -n "$candidate" ] && [ -d "$candidate" ] && [ -f "$candidate/std.ndll" ]
}

resolve_system_nekopath_dir() {
  local candidate=""
  local -a candidates=()

  candidates+=("/usr/lib/neko")
  candidates+=("/usr/lib64/neko")
  candidates+=("/usr/lib/x86_64-linux-gnu/neko")
  candidates+=("/usr/local/lib/neko")
  candidates+=("/opt/homebrew/lib/neko")

  for candidate in "${candidates[@]}"; do
    if dir_has_std_ndll "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_system_neko_bin() {
  local candidate=""
  local -a candidates=()

  candidates+=("/usr/bin/neko")
  candidates+=("/usr/local/bin/neko")
  candidates+=("/opt/homebrew/bin/neko")

  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_system_nekotools_bin() {
  local candidate=""
  local -a candidates=()

  candidates+=("/usr/bin/nekotools")
  candidates+=("/usr/local/bin/nekotools")
  candidates+=("/opt/homebrew/bin/nekotools")

  for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

is_lix_neko_shim() {
  case "${1:-}" in
    */node_modules/.bin/neko|*/lix/bin/nekoshim.js)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_nekopath_dir() {
  local candidate=""
  local -a candidates=()

  if [ -n "${NEKOPATH:-}" ]; then
    candidates+=("${NEKOPATH}")
  fi
  candidates+=("$(cd "$(dirname "$STAGE0_NEKOTOOLS")" && pwd)")
  candidates+=("$(cd "$(dirname "$STAGE0_NEKO")" && pwd)")
  candidates+=("$HOME/haxe/neko")
  candidates+=("$HOME/haxe/neko/versions/$UPSTREAM_REF")
  candidates+=("/usr/lib/neko")
  candidates+=("/usr/lib64/neko")
  candidates+=("/usr/lib/x86_64-linux-gnu/neko")
  candidates+=("/usr/local/lib/neko")
  candidates+=("/opt/homebrew/lib/neko")

  for candidate in "${candidates[@]}"; do
    if [ -d "$candidate" ] && [ -f "$candidate/std.ndll" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

NEKOPATH_DIR=""
NEKO_WRAPPER_EXPORT_NEKOPATH=1
selected_nekotools_dir="$(cd "$(dirname "$STAGE0_NEKOTOOLS")" && pwd)"
selected_neko_dir="$(cd "$(dirname "$STAGE0_NEKO")" && pwd)"

if [ -n "${NEKOPATH:-}" ] && dir_has_std_ndll "${NEKOPATH}"; then
  NEKOPATH_DIR="${NEKOPATH}"
elif dir_has_std_ndll "$selected_neko_dir"; then
  NEKOPATH_DIR="$selected_neko_dir"
elif dir_has_std_ndll "$selected_nekotools_dir"; then
  NEKOPATH_DIR="$selected_nekotools_dir"
else
  if is_lix_neko_shim "$STAGE0_NEKO"; then
    NEKOPATH_DIR="$(resolve_nekopath_dir || true)"
    NEKO_WRAPPER_EXPORT_NEKOPATH=0
  else
    system_neko="$(resolve_system_neko_bin || true)"
    system_nekotools="$(resolve_system_nekotools_bin || true)"
    system_nekopath_dir="$(resolve_system_nekopath_dir || true)"
    if [ -n "$system_neko" ] && [ -x "$system_neko" ] && [ -n "$system_nekotools" ] && [ -x "$system_nekotools" ] && [ -n "$system_nekopath_dir" ]; then
      STAGE0_NEKO="$system_neko"
      STAGE0_NEKOTOOLS="$system_nekotools"
      NEKOPATH_DIR="$system_nekopath_dir"
    else
      NEKOPATH_DIR="$(resolve_nekopath_dir || true)"
    fi
  fi
fi

if [ -n "$NEKOPATH_DIR" ]; then
  echo "Using Neko binaries: neko=${STAGE0_NEKO} nekotools=${STAGE0_NEKOTOOLS}" >&2
  echo "Using NEKOPATH directory: ${NEKOPATH_DIR}" >&2
else
  echo "Warning: Could not resolve NEKOPATH directory containing std.ndll; preserving system defaults." >&2
fi

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

  python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" skip-sys-on-macos --upstream-dir "$UPSTREAM_DIR"
}



patch_runci_js_server_timeouts_on_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    return 0
  fi
  if [ "${HXHX_GATE3_FORCE_JS_SERVER:-0}" = "1" ]; then
    return 0
  fi

  local test_builder="$UPSTREAM_DIR/tests/server/src/utils/macro/TestBuilder.macro.hx"
  local test_case="$UPSTREAM_DIR/tests/server/src/TestCase.hx"
  [ -f "$test_builder" ] || return 0
  [ -f "$test_case" ] || return 0

  python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" js-server-timeouts-on-macos --upstream-dir "$UPSTREAM_DIR" --timeout-ms "$HXHX_GATE3_JS_SERVER_TIMEOUT_MS"
}
patch_runci_skip_utest_install_if_present() {
  local run_ci="$UPSTREAM_DIR/tests/RunCi.hx"
  [ -f "$run_ci" ] || return 0

  # Upstream RunCi installs utest via network. If utest is already available in the local
  # `.haxelib/` repo, skip the install.
  python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" skip-utest-install-if-present --upstream-dir "$UPSTREAM_DIR"
}

seed_local_haxelib_dev_from_global() {
  local lib="$1"
  local enabled="${2:-1}"
  if [ "$enabled" != "1" ]; then
    return 0
  fi

  local root=""
  root="$("${STAGE0_HAXELIB}" --global libpath "$lib" 2>/dev/null || true)"
  if [ -z "$root" ] || [ ! -d "$root" ]; then
    return 0
  fi

  # This uses the local `.haxelib/` repo (created in the worktree) because haxelib searches upwards.
  PATH="$WRAP_DIR:$PATH" haxelib dev "$lib" "$root" >/dev/null 2>&1 || true
}

patch_runci_macro_skip_haxeserver_install_if_present() {
  local macro_target="$UPSTREAM_DIR/tests/runci/targets/Macro.hx"
  [ -f "$macro_target" ] || return 0

  python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" macro-skip-haxeserver-install-if-present --upstream-dir "$UPSTREAM_DIR"
}

patch_runci_macro_optional_skip_party() {
  local macro_target="$UPSTREAM_DIR/tests/runci/targets/Macro.hx"
  [ -f "$macro_target" ] || return 0

  python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" macro-optional-skip-party --upstream-dir "$UPSTREAM_DIR"
}

patch_sourcemaps_skip_sourcemap_install_if_present() {
  local test_hx="$UPSTREAM_DIR/tests/sourcemaps/src/Test.hx"
  [ -f "$test_hx" ] || return 0

  # Upstream sourcemaps tests unconditionally do `haxelib install sourcemap`. If the lib is
  # already available in the local `.haxelib/` repo, skip the install.
  python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" sourcemaps-skip-sourcemap-install-if-present --upstream-dir "$UPSTREAM_DIR"
}

patch_runci_node_echo_server() {
  local run_ci="$UPSTREAM_DIR/tests/RunCi.hx"
  local echo_dir="$UPSTREAM_DIR/tests/echoServer"
  [ -f "$run_ci" ] || return 0
  [ -d "$echo_dir" ] || return 0

  python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" node-echo-server --upstream-dir "$UPSTREAM_DIR"
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
      if [ "$python_allow_install" != "1" ] && ! command -v pypy3 >/dev/null 2>&1; then
        die_or_skip "Missing 'pypy3' on PATH (Python target no-install mode). Install pypy3 or set HXHX_GATE3_PYTHON_ALLOW_INSTALL=1 to allow upstream installer/network fallback."
      fi
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
      if [ -z "$LUA_BIN" ] || [ ! -x "$LUA_BIN" ]; then
        die_or_skip "Missing 'lua' or 'lua5.4' on PATH (Lua target tests)."
      fi
      need_cmd luarocks "Lua target dependencies"
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
if [ -n "${NEKOPATH_DIR}" ]; then
  export NEKOPATH="${NEKOPATH_DIR}"
  export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
  export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
  export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
fi
export HAXELIB_BIN="${WRAP_DIR}/haxelib"
export LIX_BIN="${WRAP_DIR}/lix"
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
export HAXE_BIN="${STAGE0_HAXE}"
run_hxhx_filtered() {
  set +e
  if [ "\${HXHX_FORBID_STAGE0:-0}" = "1" ]; then
    "${HXHX_BIN}" "\$@" | sed -E '/^(hxhx_macro_runtime_mode=|resolved_modules=|expr_macros_expanded=|stage3=|stage3_driver=|outDir=|exe=|artifact=|run=)/d'
  else
    "${HXHX_BIN}" --compat "\$@" | sed -E '/^(hxhx_macro_runtime_mode=|resolved_modules=|expr_macros_expanded=|stage3=|stage3_driver=|outDir=|exe=|artifact=|run=)/d'
  fi
  local code="\${PIPESTATUS[0]}"
  set -e
  return "\$code"
}
if [ "\${HXHX_RUNCI_FILTER_STAGE3_OUTPUT:-1}" = "1" ]; then
  run_hxhx_filtered "\$@"
  exit "\$?"
fi
if [ "\${HXHX_FORBID_STAGE0:-0}" = "1" ]; then
  exec "${HXHX_BIN}" "\$@"
fi
exec "${HXHX_BIN}" --compat "\$@"
EOF
chmod +x "$WRAP_DIR/haxe"

cat >"$WRAP_DIR/lix" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "run-haxelib" ]; then
  shift
  exec "${STAGE0_HAXELIB}" "\$@"
fi
if [ -x "${ROOT}/node_modules/.bin/lix" ]; then
  exec "${ROOT}/node_modules/.bin/lix" "\$@"
fi
exec lix "\$@"
EOF
chmod +x "$WRAP_DIR/lix"

cat >"$WRAP_DIR/haxelib" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${NEKOPATH_DIR}" ]; then
  export NEKOPATH="${NEKOPATH_DIR}"
  export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
  export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
  export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
fi
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
if [ "\${1:-}" = "path" ]; then
  retries="\${HXHX_HAXELIB_PATH_RETRIES:-3}"
  delay="\${HXHX_HAXELIB_PATH_RETRY_DELAY_SEC:-1}"
  if [ "\$retries" -lt 1 ] 2>/dev/null; then
    retries=1
  fi
  for attempt in \$(seq 1 "\$retries"); do
    set +e
    "${STAGE0_HAXELIB}" "\$@"
    code="\$?"
    set -e
    if [ "\$code" -eq 0 ]; then
      exit 0
    fi
    if [ "\$code" -eq 244 ] && [ "\$attempt" -lt "\$retries" ]; then
      sleep "\$delay"
      continue
    fi
    exit "\$code"
  done
  exit 1
fi
exec "${STAGE0_HAXELIB}" "\$@"
EOF
chmod +x "$WRAP_DIR/haxelib"

cat >"$WRAP_DIR/nekotools" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${NEKOPATH_DIR}" ]; then
  export NEKOPATH="${NEKOPATH_DIR}"
  export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
  export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
  export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
fi
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
exec "${STAGE0_NEKOTOOLS}" "\$@"
EOF
chmod +x "$WRAP_DIR/nekotools"

cat >"$WRAP_DIR/neko" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "${NEKO_WRAPPER_EXPORT_NEKOPATH}" = "1" ] && [ -n "${NEKOPATH_DIR}" ]; then
  export NEKOPATH="${NEKOPATH_DIR}"
  export LD_LIBRARY_PATH="${NEKOPATH_DIR}:\${LD_LIBRARY_PATH:-}"
  export DYLD_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_LIBRARY_PATH:-}"
  export DYLD_FALLBACK_LIBRARY_PATH="${NEKOPATH_DIR}:\${DYLD_FALLBACK_LIBRARY_PATH:-}"
else
  unset NEKOPATH
  unset LD_LIBRARY_PATH
  unset DYLD_LIBRARY_PATH
  unset DYLD_FALLBACK_LIBRARY_PATH
fi
if [ -n "${STAGE0_STD_PATH}" ]; then
  export HAXE_STD_PATH="${STAGE0_STD_PATH}"
fi
exec "${STAGE0_NEKO}" "\$@"
EOF
chmod +x "$WRAP_DIR/neko"

cat >"$WRAP_DIR/lua" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "${LUA_BIN}" "\$@"
EOF
chmod +x "$WRAP_DIR/lua"

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

echo "== Gate 3: upstream tests/runci targets (${targets[*]}) (Macro mode: ${macro_mode}; Macro direct by default, non-Macro via hxhx stage0 shim)"
echo "== Gate 3 retry policy: count=${retry_count} targets=${retry_targets_raw} delay=${retry_delay_sec}s"
echo "== Gate 3 Python policy: install_fallback=${python_allow_install} (0=no-install default, 1=allow upstream installer)"

echo "== Gate 3 target watch: heartbeat=${target_heartbeat_sec}s timeout=${target_timeout_sec}s (0 disables each)"

strict_node_echo_server="${HXHX_GATE3_NODE_ECHO_SERVER:-${HXHX_FORBID_STAGE0:-0}}"
want_macro_patches=0
want_js_patches=0
want_node_echo_patch=0
for t in "${targets[@]}"; do
  t_norm="$(echo "$t" | tr '[:upper:]' '[:lower:]')"
  if [ "$t_norm" = "macro" ]; then
    want_macro_patches=1
  fi
  if [ "$t_norm" = "js" ]; then
    want_js_patches=1
  fi
  if [ "$strict_node_echo_server" = "1" ] && { [ "$t_norm" != "macro" ] || [ "$macro_mode" = "stage0_shim" ]; }; then
    want_node_echo_patch=1
  fi
done

if [ "$want_macro_patches" = "1" ]; then
  need_cmd python3 "patch upstream runci to reduce network dependency for Macro target"
fi
if [ "$want_js_patches" = "1" ] && [ "$(uname -s)" = "Darwin" ] && [ "${HXHX_GATE3_FORCE_JS_SERVER:-0}" != "1" ]; then
  need_cmd python3 "patch upstream runci Js/server async timeouts for macOS stability"
fi
if [ "$want_node_echo_patch" = "1" ]; then
  need_cmd python3 "patch upstream runci to use the stage0-free Node echo harness"
  need_cmd node "run the stage0-free Gate3 echo harness"
fi

(
  cd "$UPSTREAM_DIR/tests"
  if [ ! -d ".haxelib" ]; then
    PATH="$WRAP_DIR:$PATH" haxelib newrepo >/dev/null
  fi
  export UPSTREAM_DIR
  patch_runci_skip_sys_on_macos
  if [ "$want_js_patches" = "1" ]; then
    patch_runci_js_server_timeouts_on_macos
  fi
  if [ "$want_node_echo_patch" = "1" ]; then
    patch_runci_node_echo_server
  fi

  if [ "$want_macro_patches" = "1" ]; then
    # Gate runner stability patches (reduce network dependency where possible).
    patch_runci_skip_utest_install_if_present
    patch_runci_macro_skip_haxeserver_install_if_present
    patch_runci_macro_optional_skip_party
    patch_sourcemaps_skip_sourcemap_install_if_present

    # Seed local `.haxelib` from globally installed libs when present.
    seed_local_haxelib_dev_from_global utest "${HXHX_GATE2_SEED_UTEST_FROM_GLOBAL:-1}"
    seed_local_haxelib_dev_from_global haxeserver "${HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL:-1}"
    seed_local_haxelib_dev_from_global sourcemap "${HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL:-1}"
  fi
)

failures=0
summary=()

run_target_attempt() {
  local target="$1"
  local t_lower="$2"

  if [ "$t_lower" = "macro" ] && [ "$macro_mode" = "direct" ]; then
    (
      cd "$ROOT"
      HAXE_UPSTREAM_DIR="$UPSTREAM_DIR_ORIG" \
      HAXELIB_BIN="$STAGE0_HAXELIB" \
      HXHX_GATE2_MODE=stage3_no_emit_direct \
      HXHX_GATE2_SKIP_PARTY="${HXHX_GATE2_SKIP_PARTY}" \
      bash "$ROOT/scripts/hxhx/run-upstream-runci-macro.sh"
    )
  else
    (
      cd "$UPSTREAM_DIR/tests"
      if [ -n "${STAGE0_STD_PATH:-}" ]; then
        export HAXE_STD_PATH="${STAGE0_STD_PATH}"
      fi
      HXHX_GATE3_NODE_ECHO_SERVER="$strict_node_echo_server" TEST="$target" PATH="$WRAP_DIR:$PATH" "$STAGE0_HAXE" RunCi.hxml
    )
  fi
}

run_target_attempt_with_watch() {
  local target="$1"
  local t_lower="$2"
  local attempt="$3"
  local max_attempts="$4"
  local heartbeat_pid=""
  local timeout_pid=""
  local target_pid=""
  local timeout_marker=""
  local code=0

  if [ "$target_timeout_sec" -gt 0 ]; then
    timeout_marker="$(mktemp)"
  fi

  set +e
  run_target_attempt "$target" "$t_lower" &
  target_pid="$!"

  if [ "$target_heartbeat_sec" -gt 0 ]; then
    (
      local elapsed=0
      local watch_sleep_pid=""
      trap 'if [ -n "${watch_sleep_pid:-}" ]; then kill "$watch_sleep_pid" 2>/dev/null || true; fi; exit 0' TERM INT
      while kill -0 "$target_pid" 2>/dev/null; do
        sleep "$target_heartbeat_sec" &
        watch_sleep_pid="$!"
        wait "$watch_sleep_pid" || exit 0
        watch_sleep_pid=""
        elapsed=$((elapsed + target_heartbeat_sec))
        if kill -0 "$target_pid" 2>/dev/null; then
          echo "gate3_target_heartbeat target=${target} attempt=${attempt}/${max_attempts} elapsed=${elapsed}s"
        fi
      done
    ) &
    heartbeat_pid="$!"
  fi

  if [ "$target_timeout_sec" -gt 0 ]; then
    (
      local watch_sleep_pid=""
      trap 'if [ -n "${watch_sleep_pid:-}" ]; then kill "$watch_sleep_pid" 2>/dev/null || true; fi; exit 0' TERM INT
      sleep "$target_timeout_sec" &
      watch_sleep_pid="$!"
      wait "$watch_sleep_pid" || exit 0
      watch_sleep_pid=""
      if kill -0 "$target_pid" 2>/dev/null; then
        echo "Gate3 target timeout: target=${target} attempt=${attempt}/${max_attempts} exceeded ${target_timeout_sec}s." >&2
        if [ -n "$timeout_marker" ]; then
          printf 'timeout\n' >"$timeout_marker"
        fi
        kill "$target_pid" 2>/dev/null || true
        sleep 2
        if kill -0 "$target_pid" 2>/dev/null; then
          kill -9 "$target_pid" 2>/dev/null || true
        fi
      fi
    ) &
    timeout_pid="$!"
  fi

  wait "$target_pid"
  code="$?"
  set -e

  if [ -n "$heartbeat_pid" ]; then
    kill "$heartbeat_pid" 2>/dev/null || true
    wait "$heartbeat_pid" 2>/dev/null || true
  fi

  if [ -n "$timeout_pid" ]; then
    kill "$timeout_pid" 2>/dev/null || true
    wait "$timeout_pid" 2>/dev/null || true
  fi

  if [ -n "$timeout_marker" ]; then
    if [ -s "$timeout_marker" ]; then
      code=124
    fi
    rm -f "$timeout_marker"
  fi

  return "$code"
}

for target in "${targets[@]}"; do
  echo ""
  echo "== Target: $target"

  if ! preflight_target "$target"; then
    summary+=("$target: SKIP (missing deps)")
    continue
  fi

  t_lower="$(echo "$target" | tr '[:upper:]' '[:lower:]')"
  max_attempts=1
  if [ "$retry_count" -gt 0 ] && should_retry_target "$t_lower"; then
    max_attempts="$((retry_count + 1))"
  fi

  attempt=1
  start="$(date +%s)"
  while true; do
    if run_target_attempt_with_watch "$target" "$t_lower" "$attempt" "$max_attempts"; then
      code=0
    else
      code="$?"
    fi

    if [ "$code" -eq 0 ] || [ "$attempt" -ge "$max_attempts" ]; then
      break
    fi

    next_attempt="$((attempt + 1))"
    echo "Retrying target '$target' (attempt ${next_attempt}/${max_attempts}) after exit ${code}..." >&2
    if [ "$retry_delay_sec" -gt 0 ]; then
      sleep "$retry_delay_sec"
    fi
    attempt="$next_attempt"
  done
  end="$(date +%s)"
  dt="$((end - start))"
  attempts_note=""
  if [ "$attempt" -gt 1 ]; then
    attempts_note=", attempts=${attempt}/${max_attempts}"
  fi

  if [ "$code" -eq 0 ]; then
    if [ "$t_lower" = "macro" ] && [ "$macro_mode" = "direct" ]; then
      summary+=("$target: PASS (${dt}s, mode=direct${attempts_note})")
    else
      summary+=("$target: PASS (${dt}s${attempts_note})")
    fi
  else
    if [ "$t_lower" = "macro" ] && [ "$macro_mode" = "direct" ]; then
      summary+=("$target: FAIL (${dt}s, exit $code, mode=direct${attempts_note})")
    else
      summary+=("$target: FAIL (${dt}s, exit $code${attempts_note})")
    fi
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
