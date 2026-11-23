import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Compare input types and full signatures for joins with a Dynamic value with upstream Haxe 4.3.7,
	then run the native output.

	A Dynamic return or case value does not widen a concrete result: upstream unifies it with the
	result monomorph without binding it, so the other branches choose the type, in either order.
	hxhx widened to Dynamic (haxe.rtti.XmlParser.processElement). A written result type casts each
	case to it instead, so `written(...):Dynamic` keeps its Float case as Dynamic.
**/
class M14DynamicJoinTransparentTest {
	static final root = "test/fixtures/dynamic_join_transparent";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "dynamic join observer differs: " + stdout + stderr;
	}

	/** An inferred type of this fixture's module displays as `Main.Tree`; upstream prints `Tree`. **/
	static function local(display:String):String
		return StringTools.replace(display, "Main.", "");

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
		final expectedSignatures = File.getContent(root + "/expected.signatures");
		observe("node_modules/.bin/haxe", [
			"-cp",
			"test/fixtures/method_parameter_dynamic_context",
			"-cp",
			root,
			"-main",
			"Main",
			"--macro",
			"UpstreamSignatures.check(\"Main.Ops\")",
			"--no-output"
		], expectedSignatures);
		final expected = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("DYNAMIC_JOIN_TRANSPARENT_UPSTREAM:PASS");

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
							+ local(parameter.getType().unwrapNull().getDisplay()));
		// The full signatures upstream gives, `Null` wrappers and results included.
		final signatures:Array<String> = [];
		for (cls in typed.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Ops")
				for (fn in cls.getFunctions()) {
					final environment = fn.getEnvironment();
					final inputs = [
						for (parameter in environment.getParams())
							parameter.getName() + " : " + local(parameter.getType().getDisplay())
					];
					signatures.push(HxFunctionDecl.getName(fn.getSourceDeclaration()) + "=(" + inputs.join(", ") + ") -> "
						+ local(environment.getReturnType().getDisplay()));
				}
		signatures.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (signatures.join("\n") + "\n" != expectedSignatures)
			throw "dynamic join signatures differ:\n" + signatures.join("\n");
		observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (observations.join("\n") + "\n" != expectedTypes)
			throw "dynamic join input facts differ:\n" + observations.join("\n");
		final fullModule = new ResolvedModule("Main", path, ParserStage.parse(full, path));
		final fullIndex = TyperIndex.buildHeaders([fullModule]);
		final fullLoader = new ModuleLoader(classPaths, defines, fullIndex);
		fullLoader.markResolvedAlready([fullModule]);
		final program = TyperStage.typeResolvedModule(fullModule, fullIndex, fullLoader, true);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/dynamic_join_transparent");
		observe(executable, [], expected);
		Sys.println("DYNAMIC_JOIN_TRANSPARENT_NATIVE:PASS");
	}
}
