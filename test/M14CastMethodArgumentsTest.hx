import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	A call argument converts through an abstract's `@:from`/`@:to` cast method, as in Haxe 4.3.7
	(haxe_ocaml-eonvh). Fixture: `test/fixtures/cast_method_arguments`.

	Upstream types each call argument against its parameter with `cast_or_unify`
	(callUnification.ml:48-51), which applies cast methods. hxhx selected such conversions
	(TyAbstractMethodConversion) but missed two forms:
	- a cast method without a written return type (`@:from static function ofString(s:String)
	  return new Length(s.length)`): its result is now the body's inferred result;
	- a static `@:to` method that takes the underlying value, as Map's
	  `toStringMap<K:String, V>(t:IMap<K, V>):StringMap<V>`: it now binds its argument from the
	  source's underlying type, and the call passes that representation-preserving view.
	A cast ranks below a direct match, as upstream's rate_conv adds one per abstract conversion
	(src/codegen/overloads.ml:131-200).

	- `Main`: hxhx must type it, and the js-native build must print what upstream prints.
	- `OverloadPick`: the direct `pick(s:String):String` wins for a String, and the cast overload
	  `pick(length:Length):Int` for a Length; the assignments type only with that choice.
	- `Wrong`: `measure(3)` fails, as upstream reports ("Int should be Length").
	- `OverloadWrong`: `final wrong:Int = Picker.pick("abc")` fails with "String should be Int".
**/
class M14CastMethodArgumentsTest {
	static inline final ROOT = "test/fixtures/cast_method_arguments";

	static function main():Void {
		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		requireUpstreamError("Wrong", "Wrong.hx:6: characters 11-12 : Int should be Length");
		requireUpstreamTypes("OverloadPick");
		requireUpstreamError("OverloadWrong", "OverloadWrong.hx:3: characters 3-53 : String should be Int", true);

		typeModule("Main");
		typeModule("OverloadPick");
		requireRejected("Wrong", "Wrong.hx:6:", "measure");
		requireRejected("OverloadWrong", "OverloadWrong.hx:3:", "String should be Int");

		final out = ".tmp/m14-cast-method-arguments";
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
		Sys.println("M14_CAST_METHOD_ARGUMENTS:PASS");
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
