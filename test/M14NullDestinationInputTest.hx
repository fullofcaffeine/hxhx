import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Compare input types around untyped arguments assigned to `Null<T>` destinations with upstream
	Haxe 4.3.7, check the full (wrapped) types, then run the native output.

	Upstream's unify binds an unbound monomorph to the whole destination, so `counter.count = c`
	with `count:Null<Int>` gives `c : Null<Int>` (haxe.io.Path.withExtension has this shape).
	hxhx bound the value inside the wrapper and gave `c : Int` (haxe_ocaml-p92xk). The upstream
	observer reads through `Null`, so the wrapped types are checked separately below.
**/
class M14NullDestinationInputTest {
	static final root = "test/fixtures/null_destination_input";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "null destination input observer differs: " + stdout + stderr;
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
		Sys.println("NULL_DESTINATION_INPUT_UPSTREAM:PASS");

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
		// The wrapped types upstream gives, which the observer above reads through.
		final wrapped:Array<String> = [];
		for (cls in typed.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Ops")
				for (fn in cls.getFunctions())
					for (parameter in fn.getEnvironment().getParams())
						wrapped.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "." + parameter.getName() + "=" + parameter.getType().getDisplay());
		wrapped.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		final expectedWrapped = "boundFirst.c=Int\nsetCount.c=Null<Int>\nwithLabel.ext=Null<String>";
		if (wrapped.join("\n") != expectedWrapped)
			throw "null destination input wrapped types differ:\n" + wrapped.join("\n");
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join("\n") + "\n" != expectedTypes)
			throw "null destination input input facts differ:\n" + observations.join("\n");
		final fullModule = new ResolvedModule("Main", path, ParserStage.parse(full, path));
		final fullIndex = TyperIndex.buildHeaders([fullModule]);
		final fullLoader = new ModuleLoader(classPaths, defines, fullIndex);
		fullLoader.markResolvedAlready([fullModule]);
		final program = TyperStage.typeResolvedModule(fullModule, fullIndex, fullLoader, true);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/null_destination_input");
		observe(executable, [], expected);
		Sys.println("NULL_DESTINATION_INPUT_NATIVE:PASS");
	}
}
