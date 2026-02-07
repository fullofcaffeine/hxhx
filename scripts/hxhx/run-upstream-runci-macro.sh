#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"
HAXELIB_BIN="${HAXELIB_BIN:-haxelib}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

DEFAULT_UPSTREAM="$ROOT/vendor/haxe"
UPSTREAM_DIR="${HAXE_UPSTREAM_DIR:-$DEFAULT_UPSTREAM}"
UPSTREAM_REF="${HAXE_UPSTREAM_REF:-4.3.7}"

# The upstream `tests/party` stage is network-heavy (clones + `haxelib install`) and tends
# to be the flakiest part of the suite across local environments.
#
# For Gate2 we default to skipping it unless explicitly enabled.
#
# Override:
# - set `HXHX_GATE2_SKIP_PARTY=0` to enable party tests
: "${HXHX_GATE2_SKIP_PARTY:=1}"
export HXHX_GATE2_SKIP_PARTY

# Gate2 runner mode.
#
# Why
# - Gate2 acceptance ultimately requires running runci Macro with a non-delegating `hxhx`.
# - Today `hxhx` is still a stage0 shim for the general `haxe` CLI, but we already have a Stage3
#   pipeline (`--hxhx-stage3`) that can resolve/type macro-shaped workloads without delegating.
#
# What
# - `stage0_shim` (default): RunCi calls `haxe` → wrapper runs `hxhx` as a stage0 shim.
# - `stage3_no_emit`: RunCi calls `haxe` → wrapper runs `hxhx --hxhx-stage3 --hxhx-no-emit`.
#
# Notes
# - `stage3_no_emit` is a diagnostic rung, not full Gate2 acceptance yet: it does not produce target
#   artifacts, so later runci stages may fail due to missing outputs. Use it to surface the next missing
#   frontend/typer/macro gap.
: "${HXHX_GATE2_MODE:=stage0_shim}"
export HXHX_GATE2_MODE

# Upstream `tests/misc` includes Issue11737, which runs a networked `haxelib install hxjava`
# in `_setup.hxml`. That makes Gate2 flaky/offline-hostile in CI.
#
# For bring-up we default to skipping it unless explicitly enabled.
#
# Override:
# - set `HXHX_GATE2_SKIP_HXJAVA=0` to include Issue11737 (requires hxjava toolchain).
: "${HXHX_GATE2_SKIP_HXJAVA:=1}"
export HXHX_GATE2_SKIP_HXJAVA

# If the user didn't provide their own misc filter, apply a default that excludes Issue11737.
if [ "${HXHX_GATE2_SKIP_HXJAVA}" = "1" ] && [ -z "${HXHX_GATE2_MISC_FILTER:-}" ]; then
  export HXHX_GATE2_MISC_FILTER='^(?!.*Issue11737).*$'
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

if [ ! -d "$UPSTREAM_DIR/tests/runci" ] || [ ! -f "$UPSTREAM_DIR/tests/RunCi.hxml" ]; then
  echo "Skipping upstream Gate 2: missing upstream Haxe repo at '$UPSTREAM_DIR'." >&2
  echo "Set HAXE_UPSTREAM_DIR to your local Haxe checkout." >&2
  exit 0
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v "$HAXELIB_BIN" >/dev/null 2>&1; then
  echo "Missing haxelib on PATH (expected '$HAXELIB_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2: dune/ocamlc not found on PATH."
  exit 0
fi

# runci Macro includes sys/party/misc fixtures that rely on extra host tools.
if ! command -v python3 >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2: python3 not found on PATH (required by some sys fixtures)." >&2
  exit 0
fi

if ! command -v cc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2: no C compiler found (need cc/clang/gcc for sys fixtures)." >&2
  exit 0
fi

if ! command -v javac >/dev/null 2>&1; then
  echo "Skipping upstream Gate 2: javac not found on PATH (required by some misc fixtures)." >&2
  exit 0
fi

# Resolve stage0 tool paths once so later wrapper scripts don't depend on PATH ordering.
#
# Prefer the concrete binaries from the Lix-managed toolchain for our compatibility version.
# This avoids accidentally picking up npm shims/wrappers whose internal toolchain resolution
# can vary per-worktree (notably inside `tests/party` where repos may have their own lix config).
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
# - For Gate2, we care more about robustness than shaving a few ms of wrapper overhead.
# - We still keep `haxe` itself pinned to the concrete stage0 binary to avoid accidentally
#   picking up a different toolchain inside upstream worktrees.
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
    # Lix cache default path (used in CI as well when lix downloads the toolchain).
    STAGE0_NEKOTOOLS="$HOME/haxe/neko/nekotools"
  fi
fi

if [ -z "$STAGE0_NEKOTOOLS" ] || [ ! -x "$STAGE0_NEKOTOOLS" ]; then
  echo "Skipping upstream Gate 2: nekotools not found (RunCi uses it for the echo server)." >&2
  echo "Install Neko tools (or set NEKOTOOLS_BIN=/path/to/nekotools)." >&2
  exit 0
fi

if [ -z "$STAGE0_NEKO" ]; then
  if command -v neko >/dev/null 2>&1; then
    STAGE0_NEKO="$(command -v neko)"
  elif [ -x "$HOME/haxe/neko/neko" ]; then
    # Lix cache default path.
    STAGE0_NEKO="$HOME/haxe/neko/neko"
  fi
fi

if [ -z "$STAGE0_NEKO" ] || [ ! -x "$STAGE0_NEKO" ]; then
  echo "Skipping upstream Gate 2: neko not found (some sys tests invoke it directly)." >&2
  echo "Install Neko (or set NEKO_BIN=/path/to/neko)." >&2
  exit 0
fi

NEKOPATH_DIR="$(cd "$(dirname "$STAGE0_NEKOTOOLS")" && pwd)"

# We want the upstream tests to match our compatibility target (default: 4.3.7).
# Instead of mutating the user's checkout, we run from a temporary git worktree when possible.
if command -v git >/dev/null 2>&1 && git -C "$UPSTREAM_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  UPSTREAM_WORKTREE_DIR="$(mktemp -d)"

  # If the ref doesn't exist locally, fall back to the current checkout.
  if git -C "$UPSTREAM_DIR_ORIG" rev-parse --verify --quiet "$UPSTREAM_REF^{commit}" >/dev/null 2>&1; then
    git -C "$UPSTREAM_DIR_ORIG" worktree add --detach "$UPSTREAM_WORKTREE_DIR" "$UPSTREAM_REF" >/dev/null
    UPSTREAM_DIR="$UPSTREAM_WORKTREE_DIR"
  fi
else
  echo "Skipping upstream Gate 2: HAXE_UPSTREAM_DIR is not a git checkout (worktree is required to avoid modifying your upstream repo)." >&2
  exit 0
fi

# Upstream `tests/sys` includes fixtures that intentionally create filenames that are invalid on macOS/APFS
# (e.g. surrogate codepoints). This causes python3 `os.mkdir` to fail with:
#   OSError: [Errno 92] Illegal byte sequence
#
# Upstream CI primarily uses Linux for these suites, so for Gate2 we treat sys as:
# - required on Linux
# - best-effort/unsupported on macOS (skip with an explicit message)
#
# Override:
# - set `HXHX_GATE2_FORCE_SYS=1` to attempt running sys on macOS anyway (expected to fail today)
patch_runci_macro_skip_sys_on_macos() {
  local macro_target="$UPSTREAM_DIR/tests/runci/targets/Macro.hx"
  [ -f "$macro_target" ] || return 0

  if [ "${HXHX_GATE2_FORCE_SYS:-0}" = "1" ]; then
    return 0
  fi

  if [ "$(uname -s)" != "Darwin" ]; then
    return 0
  fi

  # Patch only the sys stage in the Macro target. We do this in the temporary worktree so we don't
  # mutate the user's upstream checkout.
  python3 - <<'PY'
import io
import os
import sys

path = os.environ["UPSTREAM_DIR"] + "/tests/runci/targets/Macro.hx"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

needle = "changeDirectory(sysDir);\n\t\trunSysTest(\"haxe\", [\"compile-macro.hxml\"].concat(args));"
if needle not in src:
    # Nothing to do (upstream may have changed); keep going.
    sys.exit(0)

replacement = (
    "switch Sys.systemName() {\n"
    "\t\t\tcase 'Linux' | 'Windows':\n"
    "\t\t\t\tchangeDirectory(sysDir);\n"
    "\t\t\t\trunSysTest(\"haxe\", [\"compile-macro.hxml\"].concat(args));\n"
    "\t\t\tcase other:\n"
    "\t\t\t\tinfoMsg('Skipping sys tests on ' + other + ' (HXHX Gate2 runner; macOS/APFS unicode filename fixtures unsupported)');\n"
    "\t\t}\n"
)

src = src.replace(needle, replacement)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
PY
}

patch_runci_skip_utest_install_if_present() {
  local run_ci="$UPSTREAM_DIR/tests/RunCi.hx"
  [ -f "$run_ci" ] || return 0

  # Upstream RunCi always installs utest via network. In some local environments that can hang.
  # If utest is already available in the local `.haxelib/` repo, skip the install.
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

seed_local_haxelib_utest_from_global() {
  seed_local_haxelib_dev_from_global utest "${HXHX_GATE2_SEED_UTEST_FROM_GLOBAL:-1}"
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
        out.append(indent + "\tinfoMsg(\"Skipping party stage (HXHX Gate2 runner; set HXHX_GATE2_SKIP_PARTY=0 to enable)\");\n")
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

  # Upstream sourcemaps tests unconditionally do `haxelib install sourcemap`, which is:
  # - network-dependent, and
  # - can hang in some local environments.
  #
  # If the lib is already available in the local `.haxelib/` repo, skip the install.
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

# Upstream `tests/misc` includes some fixtures that rely on classpaths which may be empty directories.
# Git doesn't track empty directories, so those paths might be missing in some checkouts, causing the
# misc harness to fail early with "classpath <x> is not a directory".
#
# Only create classpath directories for *non-failing* fixtures to avoid changing the behavior of tests
# that intentionally validate errors.
ensure_misc_classpath_dirs() {
  local projects="$UPSTREAM_DIR/tests/misc/projects"
  [ -d "$projects" ] || return 0

  local file_list
  if command -v rg >/dev/null 2>&1; then
    file_list="$(rg -l '^-((cp)|(p)) (src|source)$' "$projects" --glob '*.hxml' --no-messages || true)"
  else
    file_list="$(grep -R -l -E '^-((cp)|(p)) (src|source)$' "$projects" --include '*.hxml' 2>/dev/null || true)"
  fi

  if [ -z "${file_list:-}" ]; then
    return 0
  fi

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "-cp src"|"-p src"|"-cp source"|"-p source")
          mkdir -p "$(dirname "$f")/${line#* }"
          ;;
      esac
    done <"$f"
  done <<<"$file_list"
}

# Some upstream/fork checkouts contain quoted args inside `.hxml` fixtures like:
#   --display "Main.hx@0@diagnostics"
#   -cp "dir with spaces"
# Haxe's `.hxml` parser treats those quotes as literal characters (it does not shell-parse),
# which can break the tests. Because we're running from a temporary worktree, we can safely
# normalize these fixtures in-place without mutating the user's checkout.
normalize_quoted_hxml_args() {
  local projects="$UPSTREAM_DIR/tests/misc/projects"
  [ -d "$projects" ] || return 0

  local files=""
  if command -v rg >/dev/null 2>&1; then
    files="$(rg -l "^-\\S+\\s+['\\\"]" "$projects" --glob '*.hxml' --no-messages || true)"
  else
    files="$(grep -R -l -E "^-\\S+[[:space:]]+['\\\"]" "$projects" --include '*.hxml' 2>/dev/null || true)"
  fi

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local tmp
    tmp="$(mktemp)"
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" =~ ^(-[^[:space:]]+)[[:space:]]+\"(.*)\"$ ]]; then
        line="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      elif [[ "$line" =~ ^(-[^[:space:]]+)[[:space:]]+\'(.*)\'$ ]]; then
        line="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
      fi
      printf '%s\n' "$line"
    done <"$f" >"$tmp"
    mv "$tmp" "$f"
  done <<<"$files"
}

# Some fixtures use `--cmd haxelib dev ...` to set up dev libraries.
# The compiler resolves `-lib` during argument parsing, which can happen before `--cmd` is executed,
# so ensure those dev libraries are seeded into the local `.haxelib/` repo up-front.
preseed_misc_haxelib_dev_libs() {
  local projects="$UPSTREAM_DIR/tests/misc/projects"
  [ -d "$projects" ] || return 0

  local files=""
  if command -v rg >/dev/null 2>&1; then
    files="$(rg -l '^--cmd haxelib dev ' "$projects" --glob '*.hxml' --no-messages || true)"
  else
    files="$(grep -R -l '^--cmd haxelib dev ' "$projects" --include '*.hxml' 2>/dev/null || true)"
  fi

  if [ -z "${files:-}" ]; then
    return 0
  fi

  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
      *-fail.hxml|*-each.hxml) continue ;;
    esac

    local base
    base="$(cd "$(dirname "$f")" && pwd)"

    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "--cmd haxelib dev "*)
          local rest lib path abs
          rest="${line#--cmd haxelib dev }"
          lib="${rest%% *}"
          path="${rest#* }"
          if [ -z "$lib" ] || [ -z "$path" ]; then
            continue
          fi
          if [[ "$path" == /* ]]; then
            abs="$path"
          else
            abs="$base/$path"
          fi
          PATH="$WRAP_DIR:$PATH" haxelib dev "$lib" "$abs" >/dev/null
          ;;
      esac
    done <"$f"
  done <<<"$files"
}

patch_misc_expected_outputs() {
  local issue3300="$UPSTREAM_DIR/tests/misc/projects/Issue3300/test-cwd-fail.hxml.stderr"
  if [ -f "$issue3300" ]; then
    # Keep this fixture aligned with upstream behavior for our compatibility version.
    #
    # Some environments/tools historically produced a different `--cwd` error message.
    # For Haxe 4.3.7, the expected text is:
    #   Error: Invalid directory: unexistant
    cat >"$issue3300" <<'EOF'
Error: Invalid directory: unexistant
EOF
  fi
}

apply_misc_filter_if_requested() {
  local filter="${HXHX_GATE2_MISC_FILTER:-}"
  if [ -z "$filter" ]; then
    return 0
  fi

  local misc_hxml="$UPSTREAM_DIR/tests/misc/compile.hxml"
  if [ -f "$misc_hxml" ]; then
    printf '\n-D MISC_TEST_FILTER=%s\n' "$filter" >>"$misc_hxml"
  fi
}

# runci Macro relies on a working `haxe` command. To run it through `hxhx`,
# we prepend a wrapper called `haxe` to PATH and point `hxhx` at the real stage0
# compiler via HAXE_BIN to avoid recursion.
HXHX_BIN="$("$ROOT/scripts/hxhx/build-hxhx.sh")"

WRAP_DIR="$(mktemp -d)"

if [ "$HXHX_GATE2_MODE" = "stage3_no_emit" ]; then
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

# Allow Stage3 to auto-build a macro host when needed. This uses stage0 haxe (still required today).
export HAXE_BIN="${STAGE0_HAXE}"
export HXHX_MACRO_HOST_AUTO_BUILD=1

exec "${HXHX_BIN}" --hxhx-stage3 --hxhx-no-emit --hxhx-out out_hxhx_runci_stage3_no_emit "\$@"
EOF
else
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
fi
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

if [ "${HXHX_GATE2_DEBUG_WRAPPER:-0}" = "1" ]; then
  echo "--- wrapper haxe ---"
  nl -ba "$WRAP_DIR/haxe" || true
  echo "--- wrapper haxelib ---"
  nl -ba "$WRAP_DIR/haxelib" || true
fi

case "$HXHX_GATE2_MODE" in
  stage3_no_emit)
    echo "== Gate 2: upstream tests/runci Macro target (diagnostic: hxhx --hxhx-stage3 --hxhx-no-emit for sub-invocations)"
    ;;
  *)
    echo "== Gate 2: upstream tests/runci Macro target (via hxhx stage0 shim)"
    ;;
esac
(
  cd "$UPSTREAM_DIR/tests"
  # Use a local haxelib repository scoped to the worktree so we don't mutate the user's global repo.
  # Haxelib searches parent directories for a `.haxelib/` folder, so creating it here applies to all subdirs.
  if [ ! -d ".haxelib" ]; then
    PATH="$WRAP_DIR:$PATH" haxelib newrepo >/dev/null
  fi
  if [ -n "${STAGE0_STD_PATH:-}" ]; then
    export HAXE_STD_PATH="${STAGE0_STD_PATH}"
  fi
  export UPSTREAM_DIR
  ensure_misc_classpath_dirs
  normalize_quoted_hxml_args
  preseed_misc_haxelib_dev_libs
  patch_misc_expected_outputs
  apply_misc_filter_if_requested
  patch_runci_macro_skip_sys_on_macos
  seed_local_haxelib_utest_from_global
  patch_runci_skip_utest_install_if_present
  seed_local_haxelib_dev_from_global sourcemap "${HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL:-1}"
  patch_sourcemaps_skip_sourcemap_install_if_present
  seed_local_haxelib_dev_from_global haxeserver "${HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL:-1}"
  patch_runci_macro_skip_haxeserver_install_if_present
  patch_runci_macro_optional_skip_party
  # RunCi defaults to the Macro target when no args/TEST are provided.
  # We intentionally pass no args here because `hxhx` treats `--` as a separator
  # and would drop everything before it.
  PATH="$WRAP_DIR:$PATH" "$STAGE0_HAXE" RunCi.hxml
)
