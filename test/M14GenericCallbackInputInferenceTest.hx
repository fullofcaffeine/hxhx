import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Compare omitted-input types for callbacks passed to generic methods with upstream Haxe 4.3.7,
	then type the full program with its `main`.

	Two gaps made `haxe.ds.ArraySort` fail (haxe_ocaml-q9crg):
	- Overload scoring rejected an omitted input that is still unknown against a parameter such as
	  `T->Bool` that mentions the callee's own type parameter. The binding chooses that type.
	- A recursive call inside a generic method could not fill the callee's omitted input with a type
	  that mentions the method's own `T`, because inputs never take a caller's type parameter.

	The upstream observer follows `Null<T>` to `T` and spells function types differently, so the
	test compares one spelling.

	This test does not run native output: Stage3, frozen by the 2026-11-16 architecture review,
	builds generic method shapes from the declaration header, where the omitted input of
	`Walk.count` is still unknown (haxe_ocaml-qypu2).
**/
class M14GenericCallbackInputInferenceTest {
	static final root = "test/fixtures/generic_callback_input_inference";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "generic callback input observer differs: " + stdout + stderr;
	}

	/** Upstream prints `Int -> Bool`; hxhx prints `(Int)->Bool`. Compare one spelling. **/
	static function spelling(text:String):String
		return ~/\(([^(),]+)\)->/g.replace(StringTools.replace(text, " ", ""), "$1->");

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
		Sys.println("GENERIC_CALLBACK_INPUT_UPSTREAM:PASS");

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
							+ spelling(parameter.getType().unwrapNull().getDisplay()));
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		final expectedLines = [for (line in expectedTypes.split("\n")) if (line.length > 0) spelling(line)];
		if (observations.join("\n") != expectedLines.join("\n"))
			throw "generic callback input facts differ:\n" + observations.join("\n");
		final fullModule = new ResolvedModule("Main", path, ParserStage.parse(full, path));
		final fullIndex = TyperIndex.buildHeaders([fullModule]);
		final fullLoader = new ModuleLoader(classPaths, defines, fullIndex);
		fullLoader.markResolvedAlready([fullModule]);
		TyperStage.typeResolvedModule(fullModule, fullIndex, fullLoader, true);
		Sys.println("GENERIC_CALLBACK_INPUT_FULL_PROGRAM:PASS");
	}
}
