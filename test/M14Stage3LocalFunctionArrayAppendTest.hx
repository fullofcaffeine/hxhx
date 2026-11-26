import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

/**
	An append inside a block-bodied local function emits natively (haxe_ocaml-hoxig).

	`Array.map` and `filter` are inlined into a loop that appends to the result, as an array
	comprehension does. Inside a local function with a block body, Stage3 rejected that append
	("control region has an unsupported layout or destination"). Upstream's
	`unit.HelperMacros.pipeMarkupLiteral` (a local function `loop` that calls `el.map(loop)`) has
	this shape, so its project-macro plugin could not be emitted.
	`test/fixtures/stage3_local_function_array_append` covers `map`, `filter` and comprehensions,
	with recursion and a captured local. Its program must print what haxe 4.3.7 prints
	(`expected.stdout`).
**/
class M14Stage3LocalFunctionArrayAppendTest {
	static inline final FIXTURE = "test/fixtures/stage3_local_function_array_append";

	static function main():Void {
		final expected = File.getContent(FIXTURE + "/expected.stdout");
		require(run("node_modules/.bin/haxe", ["-cp", FIXTURE, "--run", "Main"]) == expected, "upstream output differs from expected.stdout");

		final root = haxe.io.Path.normalize(".tmp/m14_stage3_local_function_array_append_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		final built = compile(root + "/fixture", FIXTURE);
		require(built.code == 0, "the fixture must build:\n" + built.output);
		final actual = run(root + "/fixture/out/out.exe", []);
		require(actual == expected, "hxhx output differs from haxe 4.3.7:\n" + actual);

		deleteRecursive(root);
		Sys.println("M14_STAGE3_LOCAL_FUNCTION_ARRAY_APPEND:PASS");
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
