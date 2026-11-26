import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	An arrow whose body is `trace(...)` returns Void, as in Haxe 4.3.7 (haxe_ocaml-n4s2a). Fixture:
	`test/fixtures/trace_arrow_result`.

	`trace` is a language operation, not a call of a declared function. The parser spells a trace
	that is a whole arrow body `__hxhx_trace_at_<line>(...)`, to keep the body's line. The typer
	did not know that spelling: it typed the call as an unknown function. An arrow passed for a
	generic callback (`f:T->Void`) then had an incomplete result (upstream issues/Issue7332), and
	with a known callback type js-native emitted a call of an undefined `__hxhx_trace_at_<line>`.
	TyTraceCall now treats that spelling as the language trace, with the recorded line.

	- `Main`: `sprite -> trace(sprite)` for `forEach<T:Basic>(items:Array<T>, f:T->Void)` and
	  `value -> trace(value)` for an unbounded `T`. hxhx must type it.
	- `Known`: arrow traces for a known callback type, one on a later line than its call. The
	  Stage3 native build must print what upstream prints, lines included (on main it failed to
	  emit). The js-native build must print the same values; it prints every trace without the
	  `file:line:` prefix, which is an older, separate gap.
	- `Wrong`: the result of `value -> trace(value)` is Void, so it cannot be an Int.
**/
class M14TraceArrowResultTest {
	static inline final ROOT = "test/fixtures/trace_arrow_result";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Known", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		requireUpstreamError("Wrong", "Wrong.hx:6: characters 3-46 : Void should be Int");

		typeModule("Main");
		typeModule("Known");
		// hxhx words this rejection as it does for any arrow with a Void result.
		requireRejected("Wrong", "Wrong.hx:6:", "inferred value Void is not compatible with Int");

		final out = ".tmp/m14-trace-arrow-result";
		compile([
			"--hxhx-backend",
			"js-native",
			"--hxhx-no-run",
			"--hxhx-out",
			out + "/js",
			"-cp",
			ROOT,
			"-main",
			"Known",
			"--js",
			out + "/js/out.js"
		]);
		require(run("node", [out + "/js/out.js"]) == withoutPositions(expected), "js-native output differs from upstream");
		compile(["--hxhx-no-run", "--hxhx-out", out + "/stage3", "-cp", ROOT, "-main", "Known"]);
		require(run(out + "/stage3/out.exe", []) == expected, "Stage3 native output differs from upstream");
		Sys.println("M14_TRACE_ARROW_RESULT:PASS");
	}

	/** Drop each line's `file:line: ` prefix. */
	static function withoutPositions(output:String):String
		return [
			for (line in output.split("\n"))
				line.indexOf(": ") < 0 ? line : line.substr(line.indexOf(": ") + 2)
		].join("\n");

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
