import haxe.io.Path;
import sys.io.File;
import sys.io.Process;

class M14RuntimeMacroSessionCallIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			fail(message);
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

	static function shellQuote(value:String):String {
		return "'" + StringTools.replace(value, "'", "'\"'\"'") + "'";
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
		final tmpRoot = ".tmp/m14_runtime_macro_session_call";
		deleteRecursive(tmpRoot);
		sys.FileSystem.createDirectory(tmpRoot);

		final testPath = Path.join([tmpRoot, "Test.hx"]);
		File.saveContent(testPath, [
			"import hxhx.macro.MacroRuntimeMode;",
			"",
			"class Test {",
			"\tstatic function main() {",
			"\t\tfinal session = MacroRuntimeMode.openSession(MacroRuntimeMode.INPROC);",
			"\t\tSys.println(session.run(\"0\"));",
			"\t\tsession.close();",
			"\t}",
			"}"
		].join("\n"));

		final outDir = Path.join([tmpRoot, "out"]);
		final compile = runShell([
			"haxe",
			"-cp " + shellQuote(tmpRoot),
			"-cp packages/hxhx/src",
			"-cp packages/hxhx-core/src",
			"-main Test",
			"-lib reflaxe.ocaml",
			"-D ocaml_output=" + shellQuote(outDir),
			"-D ocaml_build=byte",
			"--no-output"
		].join(" "));
		if (compile.code != 0)
			fail("compile failed:\nSTDOUT:\n" + compile.stdout + "\nSTDERR:\n" + compile.stderr);

		final duneBuild = runShell("dune build ./out.bc", outDir);
		if (duneBuild.code != 0)
			fail("dune build failed:\nSTDOUT:\n" + duneBuild.stdout + "\nSTDERR:\n" + duneBuild.stderr);

		final exePath = Path.join([outDir, "_build", "default", "out.bc"]);
		assertTrue(sys.FileSystem.exists(exePath), "expected built bytecode executable at " + exePath);

		final run = runShell("timeout 15s " + shellQuote(exePath));
		if (run.code != 0)
			fail("runtime session executable failed:\nSTDOUT:\n" + run.stdout + "\nSTDERR:\n" + run.stderr + "\nEXIT:" + run.code);

		assertTrue(StringTools.trim(run.stdout) == "ran:0", "expected runtime session output ran:0, got `" + StringTools.trim(run.stdout) + "`");

		deleteRecursive(tmpRoot);
	}
}
