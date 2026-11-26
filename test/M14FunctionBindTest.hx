import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	`f.bind(...)` on a function value types and runs as in Haxe 4.3.7 (haxe_ocaml-kee1x). Fixture:
	`test/fixtures/function_bind`.

	Upstream's type_bind (src/typing/calls.ml:367-445) turns a bind into variables that hold the
	callee and each bound argument, and a closure over the missing parameters; genjs prints just
	that, with no runtime helper. hxhx had no rule, so the result was unknown. TyFunctionBind now
	rewrites the call into the same shape: locals for the callee and the bound arguments, then the
	closure. Every backend sees ordinary locals and a closure, so js-native and the Stage3 OCaml
	backend both run it without a backend change.

	- `Main`: `add.bind(1)`, `add.bind(_, 2)`, a method bind that keeps its receiver (`counter.add`
	  sees a later change to `base`), a fully bound call, a bound argument evaluated once
	  (`add.bind(next())`), and a trailing optional parameter that is omitted. hxhx must type it,
	  and both the js-native and the Stage3 native builds must print what upstream prints.
	- `WrongArgument`: `add.bind("x")` fails, as upstream reports ("String should be Int").
	- `WrongResult`: `add.bind(1)(2)` is an Int, not a String.
	- `Conversion`: a bound argument that needs an abstract's `@:from` method (issues/Issue5783).
	  A call through a function value cannot run that method yet, so this bind keeps the older
	  path; hxhx must still type it.
**/
class M14FunctionBindTest {
	static inline final ROOT = "test/fixtures/function_bind";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("WrongArgument", "WrongArgument.hx:6: characters 22-25 : String should be Int");
		requireUpstreamError("WrongResult", "WrongResult.hx:6: characters 3-38 : Int should be String");
		requireUpstreamTypes("Conversion");

		typeModule("Main");
		typeModule("Conversion");
		requireRejected("WrongArgument", "WrongArgument.hx:6:", "String should be Int");
		requireRejected("WrongResult", "WrongResult.hx:6:", "Int should be String");

		final out = ".tmp/m14-function-bind";
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
		compile(["--hxhx-no-run", "--hxhx-out", out + "/stage3", "-cp", ROOT, "-main", "Main"]);
		require(run(out + "/stage3/out.exe", []) == expected, "Stage3 native output differs from upstream");
		Sys.println("M14_FUNCTION_BIND:PASS");
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
