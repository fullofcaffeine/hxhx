import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Compare input types around arrays of structures whose fields differ only by `Null` or
	optionality with upstream Haxe 4.3.7, then run the native output.

	`var ret = []; ret.push({name: n, tag: t}); Entries.tagged(ret)` gives `ret` the element type
	`{name:String, tag:Null<Int>}`, and `tagged` expects `Array<{name:String, ?tag:Int}>`. Upstream
	compares invariant type arguments with `type_eq`, which follows `Null` and does not compare the
	optional flag. hxhx rejected the call: "inferred value ... is not compatible with ..."
	(haxe_ocaml-35zls; `haxe.macro.ExprTools.map` has this shape). The fixture also covers a
	required `tag:Int` field.
**/
class M14OptionalFieldTypeEqualityTest {
	static final root = "test/fixtures/optional_field_type_equality";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "optional field type equality observer differs: " + stdout + stderr;
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
		Sys.println("OPTIONAL_FIELD_TYPE_EQUALITY_UPSTREAM:PASS");

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
			throw "optional field type equality input facts differ:\n" + observations.join("\n");
		final fullModule = new ResolvedModule("Main", path, ParserStage.parse(full, path));
		final fullIndex = TyperIndex.buildHeaders([fullModule]);
		final fullLoader = new ModuleLoader(classPaths, defines, fullIndex);
		fullLoader.markResolvedAlready([fullModule]);
		final program = TyperStage.typeResolvedModule(fullModule, fullIndex, fullLoader, true);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/optional_field_type_equality");
		observe(executable, [], expected);
		Sys.println("OPTIONAL_FIELD_TYPE_EQUALITY_NATIVE:PASS");
	}
}
