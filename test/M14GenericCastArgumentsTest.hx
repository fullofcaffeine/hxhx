import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	A call argument converts through an abstract cast into a parameter that names the called
	method's own type parameters, as in Haxe 4.3.7 (haxe_ocaml-uyvpx). Fixture:
	`test/fixtures/generic_cast_arguments`.

	Upstream unifies each argument with its parameter through the abstract's casts while the
	method's type parameters are still monomorphs (callUnification.ml:48-51, abstractCast.ml).
	hxhx compared conversions against the parameter as written, where those parameters are rigid,
	so these calls failed "No compatible method signature". TyAbstractConversionViews now lists the
	types an argument converts to (declared `to`, instance `@:to` results) and the types that
	convert into a parameter (declared `from`, `@:from` inputs); argument placement scores a view
	that fits as a cast, and generic binding reads the method's parameters through it. After
	selection the destination is concrete and the ordinary conversion emits the cast; a structure
	destination reads an abstract value through the declared `to` type that supplies it.

	- `Main`: `CustomArray` (`to Array<Int>`) for `Array<T>`, `Wrapped<Array<Int>>` (`to T`) and a
	  `ReadOnlyArray<Int>` (`to Iterable<T>`) for Lambda's `Iterable<A>`, `2` for `Lazy<A>` through
	  `@:from ofConst<T>(c:T):Lazy<T>`, and `pair<T>(a:T, b:T)` with a `Rounded` then an Int (through
	  `@:from fromFloat(v:Float)`). hxhx must type it, and the js-native build must print what
	  upstream prints.
	- `RestCall`: `Rest<Int>` for `Array<T>` through `@:to toArray`. Typed only: js-native does not
	  collect rest arguments yet (haxe_ocaml-wezog).
	- `Wrong`: `Words` (`to Array<String>`) does not fit `Array<T>` once T is Int; upstream reports
	  "Words should be Array<Int>".
**/
class M14GenericCastArgumentsTest {
	static inline final ROOT = "test/fixtures/generic_cast_arguments";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("Wrong", "Wrong.hx:9: characters 14-19 : Words should be Array<Int>");
		require(run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "RestCall", "--interp"]) == "true\n", "upstream output of RestCall changed");

		typeModule("Main");
		typeModule("RestCall");
		requireRejected("Wrong", "Wrong.hx:9:", "same");

		final out = ".tmp/m14-generic-cast-arguments";
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
		Sys.println("M14_GENERIC_CAST_ARGUMENTS:PASS");
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
