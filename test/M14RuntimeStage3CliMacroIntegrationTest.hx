import haxe.io.Path;
import sys.io.File;
import sys.io.Process;

class M14RuntimeStage3CliMacroIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
	}

	static function shellQuote(value:String):String {
		return "'" + StringTools.replace(value, "'", "'\"'\"'") + "'";
	}

	static function runShell(command:String, ?cwd:String):{code:Int, stdout:String, stderr:String} {
		final shellCommand = cwd == null ? command : ("cd " + shellQuote(cwd) + " && " + command);
		final process = new Process("sh", ["-lc", shellCommand]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function lastNonEmptyLine(text:String):String {
		if (text == null)
			return "";
		final lines = text.split("\n");
		var i = lines.length - 1;
		while (i >= 0) {
			final trimmed = StringTools.trim(lines[i]);
			if (trimmed.length > 0)
				return trimmed;
			i -= 1;
		}
		return "";
	}

	static function deleteRecursive(path:String):Void {
		if (!sys.FileSystem.exists(path))
			return;
		if (!sys.FileSystem.isDirectory(path)) {
			sys.FileSystem.deleteFile(path);
			return;
		}
		for (entry in sys.FileSystem.readDirectory(path))
			deleteRecursive(Path.join([path, entry]));
		sys.FileSystem.deleteDirectory(path);
	}

	static function main():Void {
		final repoRoot = Sys.getCwd();
		final tmpRoot = ".tmp/m14_runtime_stage3_cli_macro";
		deleteRecursive(tmpRoot);
		sys.FileSystem.createDirectory(tmpRoot);

		final projectRoot = Path.join([tmpRoot, "project"]);
		final srcDir = Path.join([projectRoot, "src"]);
		final utestDir = Path.join([projectRoot, "utest_src", "utest"]);
		final haxelibDir = Path.join([projectRoot, "haxe_libraries"]);
		sys.FileSystem.createDirectory(projectRoot);
		sys.FileSystem.createDirectory(srcDir);
		sys.FileSystem.createDirectory(utestDir);
		sys.FileSystem.createDirectory(haxelibDir);

		File.saveContent(Path.join([srcDir, "Main.hx"]), [
			"import utest.Assert;",
			"class Main {",
			"\tstatic function main() {",
			"\t\tAssert.contains(\"main\", [\"main\"], null);",
			"\t}",
			"}"
		].join("\n"));

		File.saveContent(Path.join([utestDir, "Assert.hx"]), [
			"package utest;",
			"class Assert {",
			"\tpublic static function contains(value:Dynamic, values:Array<Dynamic>, pos:Dynamic):Bool {",
			"\t\treturn values.indexOf(value) >= 0;",
			"\t}",
			"}"
		].join("\n"));

		File.saveContent(Path.join([haxelibDir, "utest.hxml"]), "-cp ../utest_src\n");

		final envHxBin = Sys.getEnv("HXHX_BIN");
		final hxBin = if (envHxBin != null && StringTools.trim(envHxBin).length > 0 && sys.FileSystem.exists(envHxBin)) {
			envHxBin;
		} else {
			final build = runShell("HXHX_BOOTSTRAP_HEARTBEAT=0 HXHX_STAGE0_OCAML_BUILD=byte bash scripts/hxhx/build-hxhx.sh", repoRoot);
			if (build.code != 0)
				fail("build-hxhx failed:\nSTDOUT:\n" + build.stdout + "\nSTDERR:\n" + build.stderr);
			final built = lastNonEmptyLine(build.stdout);
			assertTrue(built.length > 0, "expected build-hxhx to print an executable path");
			built;
		};
		final quotedHxCmd = StringTools.endsWith(hxBin, ".bc") ? ("ocamlrun " + shellQuote(hxBin)) : shellQuote(hxBin);
		final run = runShell("HAXE_STD_PATH="
			+ shellQuote(Path.join([repoRoot, "vendor", "haxe", "std"]))
			+ " timeout 20s "
			+ quotedHxCmd
			+ " --hxhx-stage3 -C "
			+ shellQuote(Path.normalize(Path.join([repoRoot, projectRoot])))
			+ " -cp src -main Main -lib utest --interp --hxhx-no-emit --macro "
			+ shellQuote("0"),
			repoRoot);
		if (run.code != 0)
			fail("stage3 cli macro executable failed:\nSTDOUT:\n" + run.stdout + "\nSTDERR:\n" + run.stderr + "\nEXIT:" + run.code);

		final stdout = run.stdout;
		assertTrue(stdout.indexOf("macro_run[0]=ran:0") >= 0, "expected CLI macro result in stdout, got:\n" + stdout);

		deleteRecursive(tmpRoot);
	}
}
