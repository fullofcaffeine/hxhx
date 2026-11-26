import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	A lambda parameter that the body only reads a field from no longer stops the call from sealing,
	as in upstream Haxe 4.3.7 (haxe_ocaml-0pwiv). Fixture: `test/fixtures/lambda_field_read`.

	`each<T>(cb:T->Void)` with `function(res) res.error` gives `res` an open structure with an
	`error` field whose value nothing uses; upstream keeps that field's type a monomorph. hxhx
	failed "inference variable remains unsolved". A field read on an ordinary inference variable
	now gives the field a deferred Dynamic default (TyInferenceSolver.field): it applies only when
	nothing else gives the field a type. An omitted method input keeps its fields open as before.

	- `Main`: hxhx must type it, and the js-native build must print what upstream prints;
	  `apply({error: "e"}, ...)` shows that a value's type still reaches the lambda.
	- `Wrong`: with `{error: 1}`, `final text:String = res.error` fails, as upstream reports.
**/
class M14LambdaFieldReadTest {
	static inline final ROOT = "test/fixtures/lambda_field_read";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("Wrong", "Wrong.hx:7: characters 4-34 : Int should be String");

		typeModule("Main");
		requireRejected("Wrong", "Wrong.hx:6:", "");

		final out = ".tmp/m14-lambda-field-read";
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
		Sys.println("M14_LAMBDA_FIELD_READ:PASS");
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
