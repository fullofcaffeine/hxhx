import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	A class without its own constructor infers its type arguments through the inherited one, as in
	upstream Haxe 4.3.7 (haxe_ocaml-q076l). Fixture: `test/fixtures/inherited_constructor_inference`.

	Upstream applies the parent's type arguments to the inherited constructor
	(typeloadFunction.ml:183-232), so `new SC2([1])` with `SC2<T> extends C2<Array<T>>` gives
	`SC2<Int>`. hxhx found no constructor on SC2 itself and constrained nothing; the argument stayed
	unsolved ("inference variable remains unsolved"), or, after haxe_ocaml-6a7w5, closed to
	Dynamic. TyFunctionInference.constrainConstructor now takes the nearest constructor owner
	(TypedConstructorPath) and passes the owner's arguments, projected from the class's own
	argument variables, to constrainMember.

	- `Main`: one and two levels of inheritance, explicit arguments, and a parent with a written
	  parameter type. hxhx must type it, and the js-native build must print what upstream prints.
	- `Wrong`: `new SC2([1]).get()[0]` is an Int, not a String, as upstream reports.
**/
class M14InheritedConstructorInferenceTest {
	static inline final ROOT = "test/fixtures/inherited_constructor_inference";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("Wrong", "Wrong.hx:3: characters 3-50 : Int should be String");

		typeModule("Main");
		requireRejected("Wrong", "Wrong.hx:3:", "Int should be String");

		final out = ".tmp/m14-inherited-constructor-inference";
		compile([
			"--hxhx-backend",
			"js-native",
			"--hxhx-no-run",
			"--hxhx-out",
			out + "/js",
			"-cp",
			ROOT,
			"-main",
			"Main",
			"--js",
			out + "/js/out.js"
		]);
		require(run("node", [out + "/js/out.js"]) == expected, "js-native output differs from upstream");
		Sys.println("M14_INHERITED_CONSTRUCTOR_INFERENCE:PASS");
	}

	static function typeModule(name:String):Void {
		final std = stdRoot();
		final defines = new haxe.ds.StringMap<String>();
		for (define in ["eval", "interp", "sys", "haxe4"])
			defines.set(define, "1");
		final path = ROOT + "/" + name + ".hx";
		final module = new ResolvedModule(name, path, ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([ROOT, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		TyperStage.typeResolvedModule(module, index, loader, true);
	}

	static function requireRejected(name:String, position:String, message:String):Void {
		try {
			typeModule(name);
		} catch (error:TyperError) {
			final text = error.toString();
			require(text.indexOf(position) >= 0 && text.indexOf(message) >= 0, name + " was rejected with another error: " + text);
			return;
		}
		throw name + " was accepted; upstream rejects it";
	}

	/** Extern overloads cannot run on eval; type them for JavaScript without output. */
	static function upstreamTypingArguments(name:String):Array<String>
		return ["-cp", ROOT, "-main", name, "-js", "out.js", "--no-output"];

	static function requireUpstreamTypes(name:String):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", upstreamTypingArguments(name));
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, "upstream no longer types " + name + ":\n" + stderr);
	}

	static function requireUpstreamError(name:String, error:String, typingOnly:Bool = false):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", typingOnly ? upstreamTypingArguments(name) : ["-cp", ROOT, "-main", name, "--interp"]);
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code != 0 && stderr.indexOf(error) >= 0, "upstream no longer rejects " + name + " with `" + error + "`:\n" + stderr);
	}

	static function compile(arguments:Array<String>):Void {
		final request = CompilationRequestContext.server(1);
		final code = Stage3Compiler.runRequest(arguments, request);
		final output = new StringBuf();
		for (event in request.output.events())
			output.add(event.text);
		request.close(code == 0);
		require(code == 0, "hxhx compile failed (" + arguments.join(" ") + "):\n" + output.toString());
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, command + " exited " + code + ": " + stderr);
		return stdout;
	}

	/** CI installs the pinned compiler through Lix; developers may set HAXE_STD_PATH. */
	static function stdRoot():String {
		final configured = Sys.getEnv("HAXE_STD_PATH");
		if (configured != null && configured != "" && sys.FileSystem.isDirectory(configured))
			return haxe.io.Path.removeTrailingSlashes(configured);
		final lixManaged = haxe.io.Path.join([Sys.getEnv("HOME"), "haxe", "versions", "4.3.7", "std"]);
		if (sys.FileSystem.isDirectory(lixManaged))
			return lixManaged;
		throw "Could not locate the Haxe 4.3.7 standard library. Set HAXE_STD_PATH or install that version through Lix.";
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}
}
