import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	A constrained method type parameter that no argument binds directly passes its bound check
	and gives the call its bound, as in upstream Haxe 4.3.7 (haxe_ocaml-lizyw). Fixture:
	`test/fixtures/constrained_result`.

	Upstream types such a parameter as a monomorph that carries its bounds
	(TestConstrainedMonomorphs). hxhx rejected every call with "Constraint check failure", because
	a parameter that no argument mentions counted as constraining. Now:
	- a parameter reached only through the result or another parameter's bound takes its bound
	  once the bound is known: `merge<A:{}, B:{}, C:A & B>` returns `{foo:Int, bar:String}` for
	  `merge({foo: 5}, {bar: "bar"})`, an intersection of structures being one structure;
	- such a parameter also closes from a dependent bound (`sorted<T:String, A:Array<T>>(arr:A)`);
	- a parameter reached only through an untyped lambda parameter fixes no type (`each<T:{}>`).
	Upstream's monomorph can still be narrowed later; that is haxe_ocaml-2darh.

	- `Main`: hxhx must type it, and the js-native build must print what upstream prints.
	- `WrongType`: `final text:String = merged.foo` is rejected with upstream's "Int should be String".
	- `WrongField`: upstream rejects `merged.oh` ("has no field oh"). hxhx accepts a missing field
	  on any structure unless HXHX_TYPER_STRICT is set (haxe_ocaml-3uu0p), so this test only
	  requires that typing it does not crash the inference solver, as it did before.
**/
class M14ConstrainedResultTest {
	static inline final ROOT = "test/fixtures/constrained_result";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("WrongType", "WrongType.hx:7: characters 3-34 : Int should be String");
		requireUpstreamError("WrongField", "{ foo : Int, bar : String } has no field oh");

		typeModule("Main");
		try {
			typeModule("WrongType");
			throw "WrongType was accepted; upstream rejects it";
		} catch (error:TyperError) {
			final text = error.toString();
			require(text.indexOf("WrongType.hx:7:") >= 0
				&& text.indexOf("Int should be String") >= 0, "WrongType was rejected with another error: " + text);
		}
		try {
			typeModule("WrongField");
		} catch (error:TyperError) {
			// A rejection is upstream's behavior (haxe_ocaml-3uu0p); any other exception is a crash.
		}

		final out = ".tmp/m14-constrained-result";
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
		Sys.println("M14_CONSTRAINED_RESULT:PASS");
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

	static function requireUpstreamError(name:String, error:String):Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", ROOT, "-main", name, "--interp"]);
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
