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
  "$fixture/tests/sys" \
  "$fixture/tests/echoServer/www" \
  "$fixture/tests/sourcemaps/src" \
  "$fixture/tests/server/src/utils/macro" \
  "$fixture/tests/server/src"

cat >"$fixture/tests/RunCi.hx" <<'EOF'
class RunCi {
	static function main() {
		if (isCi()) {
			changeDirectory('echoServer');
			runCommand('haxe', ['build.hxml']);
			changeDirectory(cwd);
		}

			//run neko-based http echo server
			var echoServer = new sys.io.Process('nekotools', ['server', '-d', 'echoServer/www/', '-p', '20200']);

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

cat >"$fixture/tests/runci/targets/Js.hx" <<'EOF'
class Js {
	static public function run(args:Array<String>) {
		changeDirectory(sysDir);
		installNpmPackages(["deasync"]);
		runCommand("haxe", ["compile-js.hxml"].concat(args));
		runSysTest("node", ["bin/js/sys.js"]);
	}
}
EOF

cat >"$fixture/tests/runci/targets/Java.hx" <<'EOF'
class Java {
	static public function run(args:Array<String>) {
		changeDirectory(sysDir);
		runCommand("haxe", ["compile-java.hxml"].concat(args));
		runSysTest("java", ["-jar", "bin/java/Main-Debug.jar"]);
	}
}
EOF

cat >"$fixture/tests/runci/targets/Python.hx" <<'EOF'
class Python {
	static public function run(args:Array<String>) {
		final pys = ["python3"];

		changeDirectory(getMiscSubDir("python"));
		runCommand("haxe", ["run.hxml"]);

		changeDirectory(getMiscSubDir('python', "pythonImport"));
		runCommand("haxe", ["compile.hxml"]);
		for (py in pys) {
			runCommand(py, ["test.py"]);
		}
	}
}
EOF

cat >"$fixture/tests/runci/targets/Lua.hx" <<'EOF'
class Lua {
	static function installLib(lib : String, version : String, ?server :String){
		if (!commandSucceed("luarocks", ["show", lib, version])) {
			final args = ["install", lib, version];
			runCommand("luarocks", args);
		}
	}

	static public function run(args:Array<String>) {
		installLib("luasec", "1.0.2-1");
		installLib("luasocket", "3.0rc1-2");
	}
}
EOF

cat >"$fixture/tests/runci/System.hx" <<'EOF'
class System {
	static public function runSysTest(cmd:String, ?args:Array<String>) {
		runCommand(cmd, args);
	}
}
EOF

cat >"$fixture/tests/sys/compile-fs.hxml" <<'EOF'
# comment the following line to disable testing the filesystem with invalid
# Unicode codepoints; these will not work on APFS

-D TEST_INVALID_UNICODE_FS
EOF

cat >"$fixture/tests/sourcemaps/src/Test.hx" <<'EOF'
class Test {
  static function main() {
    Sys.command('haxelib', ['install', 'sourcemap']);
  }
}
EOF

HXHX_PATCH_HELPER_FORCE_DARWIN=1 python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" skip-sys-on-macos --upstream-dir "$fixture"
HXHX_PATCH_HELPER_FORCE_DARWIN=1 python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" valid-unicode-fs-on-macos --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" python-skip-missing-misc --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" skip-utest-install-if-present --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" macro-skip-haxeserver-install-if-present --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" macro-optional-skip-party --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" sourcemaps-skip-sourcemap-install-if-present --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" lua-luasec-direct-rockspec --upstream-dir "$fixture"
python3 "$ROOT/scripts/hxhx/patch-upstream-runci.py" node-echo-server --upstream-dir "$fixture"

grep -Fq "HXHX Gate runner: skip JS sys compile on macOS" "$fixture/tests/runci/targets/Js.hx"
grep -Fq "Skipping JS sys tests on Mac" "$fixture/tests/runci/targets/Js.hx"
grep -Fq "HXHX Gate runner: skip Java sys compile on macOS" "$fixture/tests/runci/targets/Java.hx"
grep -Fq "Skipping Java sys tests on Mac" "$fixture/tests/runci/targets/Java.hx"
grep -Fq "HXHX Gate runner: upstream tests/sys contains unicode filename fixtures" "$fixture/tests/runci/System.hx"
grep -Fq "HXHX Gate runner: APFS rejects the invalid-Unicode filename subset" "$fixture/tests/sys/compile-fs.hxml"
if grep -Fq -- "-D TEST_INVALID_UNICODE_FS" "$fixture/tests/sys/compile-fs.hxml"; then
  echo "compile-fs.hxml still enables invalid Unicode filesystem fixtures on Darwin" >&2
  exit 1
fi
grep -Fq "HXHX Gate runner: skip missing Python misc directories" "$fixture/tests/runci/targets/Python.hx"
grep -Fq "Skipping Python misc tests" "$fixture/tests/runci/targets/Python.hx"
grep -Fq "Skipping Python import misc tests" "$fixture/tests/runci/targets/Python.hx"
grep -Fq 'runCommand("haxelib", ["path", "utest"])' "$fixture/tests/RunCi.hx"
grep -Fq 'runCommand("haxelib", ["path", "haxeserver"])' "$fixture/tests/runci/targets/Macro.hx"
grep -Fq "HXHX_GATE2_SKIP_PARTY" "$fixture/tests/runci/targets/Macro.hx"
grep -Fq "['path', 'sourcemap']" "$fixture/tests/sourcemaps/src/Test.hx"
grep -Fq "HXHX_GATE3_LUASEC_DIRECT_ROCKSPEC" "$fixture/tests/runci/targets/Lua.hx"
grep -Fq "installLibFromPinnedRock" "$fixture/tests/runci/targets/Lua.hx"
grep -Fq "https://luarocks.org/luasocket-3.0rc1-2.src.rock" "$fixture/tests/runci/targets/Lua.hx"
grep -Fq "raw.githubusercontent.com/lunarmodules/luasec/v1.0.2/luasec-1.0.2-1.rockspec" "$fixture/tests/runci/targets/Lua.hx"
grep -Fq "HXHX_GATE3_NODE_ECHO_SERVER" "$fixture/tests/RunCi.hx"
grep -Fq "hxhx_node_echo_server.js" "$fixture/tests/RunCi.hx"
grep -Fq "nekotools" "$fixture/tests/RunCi.hx"
grep -Fq "createServer" "$fixture/tests/echoServer/hxhx_node_echo_server.js"

echo "gate3 patch helper fixture OK"
