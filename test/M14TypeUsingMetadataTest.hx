import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Compare input types around calls through a type's `@:using` metadata with upstream Haxe 4.3.7,
	then type the full program with its `main` and the modules it loads.

	`result.resolve()` for `@:using(pk.Res.ResTools) enum Res<T>` calls `ResTools.resolve(result)`
	without a `using` line. hxhx read only the module's own `using` lines, so the call had no
	declaration and its result was `Dynamic` (haxe_ocaml-a0cm3; eval's `sys.thread.EventLoop`
	calls `LuvTimer.init(handle).resolve()` this way).

	This test does not run native output: Stage3, frozen by the 2026-11-16 architecture review,
	has no representation for a generic enum such as `Res<T>`.

	The upstream observer follows `Null<T>` to `T`, so the hxhx side drops a `Null` wrapper.
**/
class M14TypeUsingMetadataTest {
	static final root = "test/fixtures/type_using_metadata";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "type using observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final expectedTypes = File.getContent(root + "/expected.types");
		observe("node_modules/.bin/haxe", [
			"-cp",
			"test/fixtures/method_parameter_dynamic_context",
			"-cp",
			root,
			"-main",
			"Main",
			"--macro",
			"UpstreamTypes.check(\"Main.Ops\")",
			"--no-output"
		], expectedTypes);
		final expected = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("TYPE_USING_UPSTREAM:PASS");

		final path = root + "/Main.hx";
		// Type the operations alone. With the calls in `main`, call-site evidence would supply the
		// types, and the check would not show what the method bodies imply.
		final full = File.getContent(path);
		final operationsOnly = full.substr(0, full.indexOf("class Main {")) + "class Main {\n\tstatic function main() {}\n}\n";
		final module = new ResolvedModule("Main", path, ParserStage.parse(operationsOnly, path));
		// Array access needs the standard library's Array, so type with a module loader, as the
		// typed oracle does.
		final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final standardRoot = haxe.io.Path.removeTrailingSlashes(Stage1Args.getStandardLibraryRoot(arguments));
		final classPaths = [root, standardRoot + "/eval/_std", standardRoot];
		final defines = new haxe.ds.StringMap<String>();
		for (name in ["eval", "interp", "sys", "haxe4"])
			defines.set(name, "1");
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(classPaths, defines, index);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final observations:Array<String> = [];
		for (cls in typed.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Ops")
				for (fn in cls.getFunctions())
					for (parameter in fn.getEnvironment().getParams())
						observations.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "." + parameter.getName() + "="
							+ parameter.getType().unwrapNull().getDisplay());
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join("\n") + "\n" != expectedTypes)
			throw "type using input facts differ:\n" + observations.join("\n");
		// Type `Main` and every module that typing loads, `pk.Res` and its provider included.
		M14Stage3RuntimeFixture.prepareProgram({source: full, path: path, root: root});
		Sys.println("TYPE_USING_FULL_PROGRAM:PASS");
	}
}
