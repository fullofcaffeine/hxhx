#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$ROOT/.tmp/gate3-patch-helper-fixture.$$"

cleanup() {
  rm -rf "$fixture" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf "$fixture"
mkdir -p \
  "$fixture/tests/runci/targets" \
  "$fixture/tests/sourcemaps/src" \
  "$fixture/tests/server/src/utils/macro" \
  "$fixture/tests/server/src"

cat >"$fixture/tests/RunCi.hx" <<'EOF'
class RunCi {
  static function main() {
    haxelibInstallGit("haxe-utest", "utest", "a94f8812e8786f2b5fec52ce9f26927591d26327", "--always");
  }
}
EOF

cat >"$fixture/tests/runci/targets/Macro.hx" <<'EOF'
class Macro {
  static function run() {
    haxelibInstallGit("Simn", "haxeserver");
    deleteDirectoryRecursively(partyDir);
  }
}
EOF

cat >"$fixture/tests/sourcemaps/src/Test.hx" <<'EOF'
class Test {
  static function main() {
    Sys.command('haxelib', ['install', 'sourcemap']);
  }
}
EOF

python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" skip-utest-install-if-present --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" macro-skip-haxeserver-install-if-present --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" macro-optional-skip-party --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" sourcemaps-skip-sourcemap-install-if-present --upstream-dir "$fixture"

grep -Fq 'runCommand("haxelib", ["path", "utest"])' "$fixture/tests/RunCi.hx"
grep -Fq 'runCommand("haxelib", ["path", "haxeserver"])' "$fixture/tests/runci/targets/Macro.hx"
grep -Fq "HXHX_GATE2_SKIP_PARTY" "$fixture/tests/runci/targets/Macro.hx"
grep -Fq "['path', 'sourcemap']" "$fixture/tests/sourcemaps/src/Test.hx"

echo "gate3 patch helper fixture OK"
