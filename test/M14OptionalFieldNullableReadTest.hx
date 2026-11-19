import hxhx.Stage1Compiler.Stage1Args;
import sys.io.File;

/**
	Check that reading an optional structure field is typed `Null<T>`, as in upstream Haxe 4.3.7,
	then run the native output.

	With `typedef Entry = {name:String, ?crc:Int, ?label:String}`, upstream types `e.crc` as
	`Null<Int>` and `e.label` as `Null<String>`. hxhx typed them as `Int` and `String`
	(haxe_ocaml-mt7oe). The upstream observer follows `Null<T>` to `T` for parameters, so the test
	reads the helper methods' result types directly; the native run also checks the values.
**/
class M14OptionalFieldNullableReadTest {
	static final root = "test/fixtures/optional_field_nullable_read";

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "optional field observer differs: " + stdout + stderr;
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
		Sys.println("OPTIONAL_FIELD_NULLABLE_UPSTREAM:PASS");

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
			throw "optional field input facts differ:\n" + observations.join("\n");
		// Upstream `$type` gives `(e:Entry) -> Null<Int>` and `-> Null<String>` for these reads.
		final results = new Map<String, String>();
		for (cls in typed.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Reads")
				for (fn in cls.getFunctions())
					results.set(HxFunctionDecl.getName(fn.getSourceDeclaration()), fn.getEnvironment().getReturnType().getDisplay());
		if (results.get("crcOf") != "Null<Int>" || results.get("labelOf") != "Null<String>")
			throw "optional field reads are not nullable: crcOf=" + results.get("crcOf") + " labelOf=" + results.get("labelOf");
		final fullModule = new ResolvedModule("Main", path, ParserStage.parse(full, path));
		final fullIndex = TyperIndex.buildHeaders([fullModule]);
		final fullLoader = new ModuleLoader(classPaths, defines, fullIndex);
		fullLoader.markResolvedAlready([fullModule]);
		final program = TyperStage.typeResolvedModule(fullModule, fullIndex, fullLoader, true);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/optional_field_nullable_read");
		observe(executable, [], expected);
		Sys.println("OPTIONAL_FIELD_NULLABLE_NATIVE:PASS");
	}
}
