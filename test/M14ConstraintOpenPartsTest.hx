import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	A bound check unifies an open (unknown) part of a supplied type with the bound, as upstream
	Haxe 4.3.7 does (haxe_ocaml-rhbp9). Fixture: `test/fixtures/constraint_open_parts`.

	hxhx rejected any bound check where a type still had an open part:
	- `Std.downcast([1, 2, 3], Array)` (`downcast<T:{}, S:T>`) supplies `Array<Unknown>` from the
	  class value `Array` for the bound `Array<Int>`; the open part now reads as `Int`. A nested
	  Dynamic reads the same way, as Haxe unifies `Array<Dynamic>` with `Array<Int>`. With a Dynamic
	  source, the bound `T` is `Array<Unknown>` too, and the two open parts unify. The call's result
	  reads its open parts from the bound as well, so `x` is `Array<Int>` (`same(val, x)`, `x[0] + 1`).
	- `each<T, I:Iterator<T>>(0...3, function(x) return x)`: T is reached only through the
	  lambda's untyped parameter, so it now closes from I's bound (`IntIterator` gives Int), in
	  the check and in the call's parameter and result types.
	- `Type.enumEq(Bad(123), Bad(123))` on a GADT-style constructor supplies `BadGadt<Unknown>`;
	  an open part that the bound does not name reads as Dynamic, so it satisfies `EnumValue`.

	- `Main`: hxhx must type it, and the js-native build must print what upstream prints. Its
	  `each` has no loop body: a loop over the bounded parameter fails the js-native emit on main
	  too (haxe_ocaml-zf8x9).
	- `Wrong`: `Std.downcast([1, 2, 3], haxe.ds.StringMap)` still fails, as upstream reports.
**/
class M14ConstraintOpenPartsTest {
	static inline final ROOT = "test/fixtures/constraint_open_parts";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("Wrong", "Constraint check failure for downcast.S");

		typeModule("Main");
		try {
			typeModule("Wrong");
			throw "Wrong was accepted; upstream rejects it";
		} catch (error:TyperError) {
			final text = error.toString();
			require(text.indexOf("Wrong.hx:4:") >= 0 && text.indexOf("Constraint check failure for downcast.S") >= 0,
				"Wrong was rejected with another error: " + text);
		}

		final out = ".tmp/m14-constraint-open-parts";
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
		Sys.println("M14_CONSTRAINT_OPEN_PARTS:PASS");
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
