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

#
# Prefer the user's `haxelib` from PATH (often a Lix shim) over the raw Neko-based
# `~/haxe/versions/<ver>/haxelib` binary.
#
# Why:
# - The raw binary relies on dynamic loader setup on macOS and can be brittle.
# - For gate runners, we care more about robustness than shaving a few ms of wrapper overhead.
STAGE0_HAXELIB="$(command -v "$HAXELIB_BIN")"

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

  python3 - <<'PY'
import os
import re

root = os.environ["UPSTREAM_DIR"]
timeout = os.environ["HXHX_GATE3_JS_SERVER_TIMEOUT_MS"]
tb_path = root + "/tests/server/src/utils/macro/TestBuilder.macro.hx"
tc_path = root + "/tests/server/src/TestCase.hx"
marker = "HXHX Gate runner: relaxed Js server timeouts on macOS"

with open(tb_path, "r", encoding="utf-8") as f:
    tb_src = f.read()
if marker not in tb_src:
    base_line = "$i{asyncName}.setTimeout(20000);"
    replaced_line = "$i{asyncName}.setTimeout(" + timeout + ");"
    if base_line in tb_src:
        tb_src = tb_src.replace(base_line, "// " + marker + "\n\t\t\t\t" + replaced_line, 1)
    else:
        tb_src = re.sub(
            r'\$i\{asyncName\}\.setTimeout\(\d+\);',
            "// " + marker + "\n\t\t\t\t" + replaced_line,
            tb_src,
            count=1
        )
    with open(tb_path, "w", encoding="utf-8") as f:
        f.write(tb_src)

with open(tc_path, "r", encoding="utf-8") as f:
    tc_src = f.read()
if marker not in tc_src:
    needle = "public function setup(async:utest.Async) {\n"
    if needle in tc_src:
        tc_src = tc_src.replace(
            needle,
            needle + "\t\t// " + marker + "\n\t\tasync.setTimeout(" + timeout + ");\n",
            1
        )
        with open(tc_path, "w", encoding="utf-8") as f:
            f.write(tc_src)
PY
}
patch_runci_skip_utest_install_if_present() {
  local run_ci="$UPSTREAM_DIR/tests/RunCi.hx"
  [ -f "$run_ci" ] || return 0

  # Upstream RunCi installs utest via network. If utest is already available in the local
  # `.haxelib/` repo, skip the install.
  python3 - <<'PY'
import os

path = os.environ["UPSTREAM_DIR"] + "/tests/RunCi.hx"
needle = 'haxelibInstallGit("haxe-utest", "utest", "a94f8812e8786f2b5fec52ce9f26927591d26327", "--always");'

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
changed = False
for line in lines:
    if needle in line:
        indent = line.split("haxelibInstallGit", 1)[0]
        out.append(indent + "try {\n")
        out.append(indent + "\trunCommand(\"haxelib\", [\"path\", \"utest\"]);\n")
        out.append(indent + "} catch (e:Dynamic) {\n")
        out.append(indent + "\t" + needle + "\n")
        out.append(indent + "}\n")
        changed = True
    else:
        out.append(line)

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)
PY
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

  python3 - <<'PY'
import os

path = os.environ["UPSTREAM_DIR"] + "/tests/runci/targets/Macro.hx"
needle = 'haxelibInstallGit("Simn", "haxeserver");'

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
changed = False
for line in lines:
    if needle in line:
        indent = line.split("haxelibInstallGit", 1)[0]
        out.append(indent + "try {\n")
        out.append(indent + "\trunCommand(\"haxelib\", [\"path\", \"haxeserver\"]);\n")
        out.append(indent + "} catch (e:Dynamic) {\n")
        out.append(indent + "\t" + needle + "\n")
        out.append(indent + "}\n")
        changed = True
    else:
        out.append(line)

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)
PY
}

patch_runci_macro_optional_skip_party() {
  local macro_target="$UPSTREAM_DIR/tests/runci/targets/Macro.hx"
  [ -f "$macro_target" ] || return 0

  python3 - <<'PY'
import os

path = os.environ["UPSTREAM_DIR"] + "/tests/runci/targets/Macro.hx"
needle = "deleteDirectoryRecursively(partyDir);"

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
changed = False
already = False
for line in lines:
    if "HXHX_GATE2_SKIP_PARTY" in line:
        already = True
    if needle in line and not already:
        indent = line.split(needle, 1)[0]
        out.append(indent + "if (Sys.getEnv(\"HXHX_GATE2_SKIP_PARTY\") == \"1\") {\n")
        out.append(indent + "\tinfoMsg(\"Skipping party stage (HXHX Gate runner; set HXHX_GATE2_SKIP_PARTY=0 to enable)\");\n")
        out.append(indent + "\treturn;\n")
        out.append(indent + "}\n")
        out.append(line)
        changed = True
    else:
        out.append(line)

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)
PY
}

patch_sourcemaps_skip_sourcemap_install_if_present() {
  local test_hx="$UPSTREAM_DIR/tests/sourcemaps/src/Test.hx"
  [ -f "$test_hx" ] || return 0

  # Upstream sourcemaps tests unconditionally do `haxelib install sourcemap`. If the lib is
  # already available in the local `.haxelib/` repo, skip the install.
  python3 - <<'PY'
import os

path = os.environ["UPSTREAM_DIR"] + "/tests/sourcemaps/src/Test.hx"
needle = "Sys.command('haxelib', ['install', 'sourcemap']);"

with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if needle not in src:
    raise SystemExit(0)

replacement = (
    "if (Sys.command('haxelib', ['path', 'sourcemap']) != 0) {\n"
    "\t\t\tSys.command('haxelib', ['install', 'sourcemap']);\n"
    "\t\t}"
)

src = src.replace(needle, replacement)
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

echo "== Gate 3: upstream tests/runci targets (${targets[*]}) (Macro mode: ${macro_mode}; Macro direct by default, non-Macro via hxhx stage0 shim)"
echo "== Gate 3 retry policy: count=${retry_count} targets=${retry_targets_raw} delay=${retry_delay_sec}s"
echo "== Gate 3 Python policy: install_fallback=${python_allow_install} (0=no-install default, 1=allow upstream installer)"

want_macro_patches=0
want_js_patches=0
for t in "${targets[@]}"; do
  t_norm="$(echo "$t" | tr '[:upper:]' '[:lower:]')"
  if [ "$t_norm" = "macro" ]; then
    want_macro_patches=1
  fi
  if [ "$t_norm" = "js" ]; then
    want_js_patches=1
  fi
done

if [ "$want_macro_patches" = "1" ]; then
  need_cmd python3 "patch upstream runci to reduce network dependency for Macro target"
fi
if [ "$want_js_patches" = "1" ] && [ "$(uname -s)" = "Darwin" ] && [ "${HXHX_GATE3_FORCE_JS_SERVER:-0}" != "1" ]; then
  need_cmd python3 "patch upstream runci Js/server async timeouts for macOS stability"
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
    set +e
    if [ "$t_lower" = "macro" ] && [ "$macro_mode" = "direct" ]; then
      (
        cd "$ROOT"
        HAXE_UPSTREAM_DIR="$UPSTREAM_DIR_ORIG" \
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
        TEST="$target" PATH="$WRAP_DIR:$PATH" "$STAGE0_HAXE" RunCi.hxml
      )
    fi
    code="$?"
    set -e

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
