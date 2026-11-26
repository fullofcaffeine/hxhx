import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	`e.match(pattern)` on an enum value is a one-case switch, as in upstream Haxe 4.3.7
	(haxe_ocaml-56lt0, haxe_ocaml-d592g). Fixture: `test/fixtures/enum_value_match`.

	Upstream types `e.match(pattern)` as `switch e { case pattern: true; case _: false }` when
	`e`'s type follows to an enum, or to a `@:forward` abstract over one (typer.ml:1802-1814).
	hxhx typed the pattern as a call argument, so the wildcard in `c.match(CString(_, SingleQuotes))`
	became an unknown argument of type String and typing failed ("selected call conversion does
	not satisfy its retained parameter: unknown -> primitive:String"). This blocked std
	`haxe.macro.MacroStringTools` in a target compile.

	- `Main`: wildcards on `haxe.macro.Expr.Constant` and `FieldType` (a record payload), nested
	  constructors, constants, an or-pattern, a subject with a side effect (evaluated once per
	  call) and `EReg.match`, which stays a method call. hxhx must type it, and the js-native build
	  must print what upstream prints (`expected.stdout`).
	- `native/Main`: matches in statement and expression position, built and run with the Stage3
	  OCaml backend; it must print what upstream prints. It has its own enum because the Stage3
	  emitter has no Float enum payloads.
	- `Forwarded`: a `@:forward` abstract over an enum matches like the enum; hxhx must type it.
	  It is not emitted: a switch on such an abstract fails the js-native emit on main too
	  (haxe_ocaml-dnx6e).
	- `WrongCapture`: upstream rejects a capture variable in a `.match` pattern (matcher.ml:196).
	- `WrongType`: a constructor argument of the wrong type is an error inside the pattern, with
	  upstream's message on the pattern's line. hxhx reports the statement's column, as it does
	  for every error inside an expression (haxe_ocaml-qxtyl); upstream reports the argument's.
**/
class M14EnumValueMatchTest {
	static inline final ROOT = "test/fixtures/enum_value_match";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("WrongCapture", "WrongCapture.hx:6: characters 34-40 : Pattern variables are not allowed in .match patterns");
		requireUpstreamError("WrongType", "WrongType.hx:6: characters 32-38 : String should be Int");
		require(run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Forwarded", "--interp"]) == "true false\n", "upstream output of Forwarded changed");

		typeModule("Main");
		typeModule("Forwarded");
		requireRejected("WrongCapture", "WrongCapture.hx:6:", "Pattern variables are not allowed in .match patterns");
		requireRejected("WrongType", "WrongType.hx:6:", "String should be Int");

		final out = ".tmp/m14-enum-value-match";
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

		final native = ROOT + "/native";
		final nativeExpected = run("node_modules/.bin/haxe", ["-cp", native, "-main", "Main", "--interp"]);
		require(nativeExpected == File.getContent(native + "/expected.stdout"), "native/expected.stdout no longer matches upstream Haxe:\n" + nativeExpected);
		compile(["--hxhx-no-run", "--hxhx-out", out + "/stage3", "-cp", native, "-main", "Main"]);
		require(run(out + "/stage3/out.exe", []) == nativeExpected, "Stage3 native output differs from upstream");
		Sys.println("M14_ENUM_VALUE_MATCH:PASS");
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
