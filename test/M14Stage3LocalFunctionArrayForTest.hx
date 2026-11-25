import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

/**
	A `for` over an array inside a local function emits natively (haxe_ocaml-kmm68).

	Upstream's `UnitBuilder.readDir` is a local function that loops over a directory listing; its
	project-macro plugin could not be emitted. `test/fixtures/stage3_local_function_array_for`
	covers the loop with `return`, `continue`, and `break`. Its program must print what haxe 4.3.7
	prints (`expected.stdout`). Only an Array loop has the new adapter. Other loops do not reach it:
	the typer lowers iterator loops and rejects an unresolved iterable such as `Dynamic`.
**/
class M14Stage3LocalFunctionArrayForTest {
	static inline final FIXTURE = "test/fixtures/stage3_local_function_array_for";

	static function main():Void {
		final expected = File.getContent(FIXTURE + "/expected.stdout");
		require(run("node_modules/.bin/haxe", ["-cp", FIXTURE, "--run", "Main"]) == expected, "upstream output differs from expected.stdout");

		final root = haxe.io.Path.normalize(".tmp/m14_stage3_local_function_array_for_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		final built = compile(root + "/fixture", FIXTURE);
		require(built.code == 0, "the fixture must build:\n" + built.output);
		final actual = run(root + "/fixture/out/out.exe", []);
		require(actual == expected, "hxhx output differs from haxe 4.3.7:\n" + actual);

		deleteRecursive(root);
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_ARRAY_FOR:PASS");
	}

	static function compile(out:String, source:String):{code:Int, output:String} {
		final context = new CompilationRequestContext(0, true, false);
		final code = Stage3Compiler.runRequest(["--hxhx-no-run", "--hxhx-out", out + "/out", "-cp", source, "-main", "Main"], context);
		final text = context.output.events().map(event -> event.text).join("");
		context.close(code == 0);
		return {code: code, output: text};
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, command + " exited " + code + ": " + errors);
		return output;
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(path + "/" + entry);
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}
}
