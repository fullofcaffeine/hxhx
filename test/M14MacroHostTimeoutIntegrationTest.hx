import haxe.io.Path;
import hxhx.macro.MacroHostClient;
import sys.FileSystem;
import sys.io.File;

class M14MacroHostTimeoutIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function expectContains(label:String, actual:String, expected:String):Void {
		if (actual.indexOf(expected) >= 0)
			return;
		fail(label + ': expected "' + expected + '" in "' + actual + '"');
	}

	static function mkTempDir(base:String):String {
		var i = 0;
		while (i < 1000) {
			final candidate = Path.join([base, "macro-timeout-" + Std.string(i)]);
			if (!FileSystem.exists(candidate)) {
				FileSystem.createDirectory(candidate);
				return candidate;
			}
			i++;
		}
		fail("failed to allocate temp directory");
		return "";
	}

	static function removeDirRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}
		for (entry in FileSystem.readDirectory(path)) {
			removeDirRecursive(Path.join([path, entry]));
		}
		FileSystem.deleteDirectory(path);
	}

	static function main():Void {
		final baseTmp = Path.join([Sys.getCwd(), ".tmp"]);
		if (!FileSystem.exists(baseTmp))
			FileSystem.createDirectory(baseTmp);
		final tempDir = mkTempDir(baseTmp);
		final hostScript = Path.join([tempDir, "hanging-macro-host.sh"]);
		final script = [
			"#!/usr/bin/env bash",
			"set -euo pipefail",
			"echo \"hxhx_macro_rpc_v=1\"",
			"if ! IFS= read -r hello; then",
			"  exit 0",
			"fi",
			"echo \"ok\"",
			"while true; do",
			"  sleep 1",
			"done"
		].join("\n") + "\n";
		File.saveContent(hostScript, script);
		if (Sys.command("chmod", ["+x", hostScript]) != 0)
			fail("chmod failed for fake macro host script");

		Sys.putEnv("HXHX_MACRO_HOST_EXE", hostScript);
		Sys.putEnv("HXHX_MACRO_HOST_IDLE_SECS", "1");
		Sys.putEnv("HXHX_MACRO_HOST_TOTAL_SECS", "4");

		var caught = "";
		try {
			MacroHostClient.selftest();
		} catch (e:String) {
			caught = e;
		}

		Sys.putEnv("HXHX_MACRO_HOST_EXE", null);
		Sys.putEnv("HXHX_MACRO_HOST_IDLE_SECS", null);
		Sys.putEnv("HXHX_MACRO_HOST_TOTAL_SECS", null);
		removeDirRecursive(tempDir);

		if (caught.length == 0)
			fail("expected macro host timeout error");
		expectContains("stall marker", caught, "MACRO_HOST_STALL_DETECTED=1");
		expectContains("timeout label", caught, "macro host timeout");
		Sys.println("OK m14 macro host timeout guard");
	}
}
