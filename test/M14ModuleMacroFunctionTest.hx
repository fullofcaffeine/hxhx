import sys.io.File;

/**
	A module-level `macro function` is a macro, as in Haxe 4.3.7 (haxe_ocaml-qaauj). Fixture:
	`test/fixtures/module_macro_function`.

	The parser recorded the `macro` modifier for a class member (`static macro function`) but not
	for a module-level function, so hxhx typed `foo()` by its declared result, the `Expr`
	structure, and `same("value", foo())` failed "No compatible method signature for same". The
	module-level modifier loop now records `macro` before `function`, and the call site treats the
	call like any other macro call (TyMacroCallSignature). Upstream's unit issues/Issue10626 and
	Issue10641 have this shape.

	The test checks the parsed modifiers, upstream's output, and that hxhx types `Main`.
**/
class M14ModuleMacroFunctionTest {
	static inline final ROOT = "test/fixtures/module_macro_function";

	static function main():Void {
		final process = new sys.io.Process("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0 && stdout == File.getContent(ROOT + "/expected.stdout"), "upstream output changed:\n" + stdout + stderr);

		final path = ROOT + "/Main.hx";
		final parsed = ParserStage.parse(File.getContent(path), path);
		final metadata = new Map<String, Array<String>>();
		for (cls in HxModuleDecl.getClasses(parsed.getDecl()))
			for (fn in HxClassDecl.getFunctions(cls))
				metadata.set(HxFunctionDecl.getName(fn), HxFunctionDecl.getMetadata(fn));
		require(metadata.get("foo").indexOf("macro") >= 0, "module-level macro function lost its modifier: " + metadata.get("foo"));
		require(metadata.get("plain").indexOf("macro") < 0, "a plain module-level function was marked macro");

		final std = stdRoot();
		final defines = new haxe.ds.StringMap<String>();
		for (define in ["eval", "interp", "sys", "haxe4"])
			defines.set(define, "1");
		final module = new ResolvedModule("Main", path, ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([ROOT, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		TyperStage.typeResolvedModule(module, index, loader, true);
		Sys.println("M14_MODULE_MACRO_FUNCTION:PASS");
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
