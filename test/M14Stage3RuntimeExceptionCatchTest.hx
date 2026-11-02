import sys.FileSystem;

/**
	Builds a program that catches failed file-system calls with the Stage3 native
	emitter and compares its output with upstream Haxe.

	Why
	- The OCaml runtime reports a failed file-system call with an OCaml
	  exception such as `Sys_error`. Stage3's generated `catch` used to match
	  only `HxRuntime.Hx_exception`, the carrier of a Haxe `throw`, so a native
	  program died with `Fatal error` where upstream Haxe ran its handler.

	What
	- `stage3_runtime_exception_catch` catches failed reads, writes, copies,
	  renames, deletions, listings, and directory changes through `Dynamic`,
	  `String`, and `haxe.Exception` handlers and prints each message.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- An OCaml `Failure`, which the runtime uses for its own invariant
	  failures, must still escape a `catch (e:Dynamic)`.
**/
class M14Stage3RuntimeExceptionCatchTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	/**
		A runtime invariant failure must stop the program, not reach a Haxe handler.

		The program raises an OCaml `Failure` through a host binding to
		`Stdlib.failwith`, which is how the runtime reports its own bugs. A
		`catch (e:Dynamic)` around it must not run, so the native program exits
		with OCaml's uncaught-exception report. Upstream has no equivalent
		failure, so only the native result is checked.
	**/
	static function invariantFailureEscapes():Void {
		final root = ".tmp/m14_stage3_runtime_exception_catch_invariant";
		deleteRecursive(root);
		FileSystem.createDirectory(root + "/src");
		final path = root + "/src/Main.hx";
		final source = "@:native(\"Stdlib\") extern class OcamlHost {\n" + "\tstatic function failwith(message:String):Void;\n" + "}\n\n" + "class Main {\n"
			+ "\tstatic function main():Void {\n" + "\t\ttry {\n" + "\t\t\tOcamlHost.failwith(\"backend invariant\");\n" + "\t\t} catch (e:Dynamic) {\n"
			+ "\t\t\tSys.println(\"caught: \" + Std.string(e));\n" + "\t\t}\n" + "\t\tSys.println(\"after\");\n" + "\t}\n" + "}\n";
		sys.io.File.saveContent(path, source);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root + "/src"});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
		final process = new sys.io.Process(executable, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		deleteRecursive(root);
		if (code == 0 || stdout != "" || stderr.indexOf("Failure(\"backend invariant\")") < 0)
			throw "runtime invariant failure must escape catch (e:Dynamic): exit=" + code + " stdout=" + stdout + " stderr=" + stderr;
		Sys.println("M14_STAGE3_RUNTIME_EXCEPTION_CATCH_INVARIANT_ESCAPES:PASS");
	}

	static function main():Void {
		final source = "test/fixtures/stage3_runtime_exception_catch";
		final path = source + "/Main.hx";
		final expected = sys.io.File.getContent(source + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_runtime_exception_catch";
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: sys.io.File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_RUNTIME_EXCEPTION_CATCH:PASS");
		invariantFailureEscapes();
	}
}
