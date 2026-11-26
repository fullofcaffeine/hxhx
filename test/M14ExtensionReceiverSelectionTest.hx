import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	Static extension selection skips a candidate whose first parameter does not accept the
	receiver, as upstream Haxe 4.3.7 does (haxe_ocaml-cd3jc). Fixture:
	`test/fixtures/extension_receiver_selection`.

	Upstream picks the first `using` candidate whose first parameter unifies with the receiver; a
	later `using` is tried first. With `BoxTools.describe(b:Box)` and `TextTools.describe(s:String)`,
	`new Box().describe()` tried `TextTools` and failed. Candidates rejected for their receiver are
	now skipped, like those rejected by a constraint (haxe_ocaml-5l9ut). A candidate that accepts
	the receiver is still selected, so its argument errors are still reported.

	- `Main`: hxhx must type it, and the js-native build must print what upstream prints.
	- `Wrong`: `count(b:Box, n:Int)` with a String accepts the receiver, so the argument error
	  stays (upstream: "String should be Int").
**/
class M14ExtensionReceiverSelectionTest {
	static inline final ROOT = "test/fixtures/extension_receiver_selection";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("Wrong", "Wrong.hx:5: characters 24-30 : String should be Int");

		typeModule("Main");
		try {
			typeModule("Wrong");
			throw "Wrong was accepted; upstream rejects it";
		} catch (error:TyperError) {
			final text = error.toString();
			require(text.indexOf("Wrong.hx:5:") >= 0 && text.indexOf("count") >= 0 && text.indexOf("has no field") < 0,
				"Wrong was rejected with another error: " + text);
		}

		final out = ".tmp/m14-extension-receiver-selection";
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
		Sys.println("M14_EXTENSION_RECEIVER_SELECTION:PASS");
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
