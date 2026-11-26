import sys.io.File;

/**
	A call may pass any expression to a macro parameter that has no written type, as in upstream
	Haxe 4.3.7 (follow-up to haxe_ocaml-q3mio). Fixture: `test/fixtures/untyped_macro_argument`.

	In the macro context upstream types a missing macro argument or result type as Expr
	(`typeloadFields.ml`, lines 1319-1320), so `Macros.show(value)` and `Macros.show("text")` both
	pass their argument as syntax. Since the target-view change, hxhx checks a macro call against
	the written signature, where such a parameter has no type, so the first call inferred the
	parameter's type and the second call failed: "No compatible method signature for show".
	Upstream's unit helper `HelperMacros.typeString(e)` has this shape (issues/Issue6836, Issue8700,
	Issue9271 in the survey).

	The test checks upstream's output, then types `Main` as a target compile.
**/
class M14UntypedMacroArgumentTest {
	static inline final ROOT = "test/fixtures/untyped_macro_argument";

	static function main():Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0 && stdout == "shown shown pair pair\nmaybe maybe maybe\n", "upstream output changed:\n" + stdout + stderr);

		final std = stdRoot();
		final defines = new haxe.ds.StringMap<String>();
		for (name in ["eval", "interp", "sys", "haxe4"])
			defines.set(name, "1");
		final path = ROOT + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([ROOT, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		try {
			TyperStage.typeResolvedModule(module, index, loader, true);
		} catch (error:TyperError) {
			throw "a macro call with an untyped parameter was rejected: " + error.toString();
		}
		Sys.println("M14_UNTYPED_MACRO_ARGUMENT:PASS");
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
