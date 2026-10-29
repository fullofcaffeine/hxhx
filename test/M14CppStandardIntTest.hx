import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Check the standard integer conversion against independent expectations and native execution. */
class M14CppStandardIntTest {
	static function main():Void {
		final root = "test/oracle/cpp_standard_int_seed";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		observe(new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]), expected, "upstream");
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Std", "Sys"]});
		final owner = fixture.index.getByFullName("Std");
		final declaration = owner.declarationForSignature(owner.staticMethod("int"));
		backend.cpp.CppManagedStandardInt.requireDeclaration(declaration);
		final parameters = declaration.getSignature().getArgs();
		final original = parameters[0];
		parameters[0] = TyType.fromHintText("Int");
		var rejected = false;
		try {
			backend.cpp.CppManagedStandardInt.requireDeclaration(declaration);
		} catch (failure:haxe.Exception) {
			rejected = failure.message.indexOf("one required Float input") >= 0;
		}
		parameters[0] = original;
		if (!rejected)
			throw "standard integer conversion accepted a changed declaration";
		final program = CppResolvedFixture.prepare(fixture);
		final directory = ".tmp/cpp-standard-int";
		final before = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		CppTargetCore.emit(program, new BackendContext(directory, null, "Main", false, fixture.defines));
		final after = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		if (before.join("\n") != after.join("\n"))
			throw "standard integer conversion changed source modules";
		// Direct runtime inputs exercise the conversion's unsupported cases without
		// depending on unrelated Math API bindings. The full source program checks
		// normal declaration selection, effects, conversions and provider ownership.
		final boundary = backend.cpp.CppManagedStandardInt.render(declaration, {
			callee: Static(StandardInt(declaration)),
			arguments: [EIdent("numericOperand")],
			destination: "converted",
			heap: "heap",
			prefix: "observer_",
			valueType: _ -> TyType.fromHintText("Dynamic"),
			renderValue: (_, root, indent) -> [indent + "++effects;", indent + root + ".set(source);"],
			acceptsStoredTransfer: (_, _) -> false
		}, "  ");
		sys.io.File.saveContent(directory + "/StdIntBoundary.inc", boundary.join("\n") + "\n");
		sys.io.File.copy("test/cpp_managed_heap/StandardIntObserver.cpp", directory + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = directory + "/observer" + optimization;
			if (Sys.command(timeout, [
				"60",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined,float-cast-overflow",
				"-fno-sanitize-recover=all",
				'-DHXHX_LOCAL_PROGRAM="src/Main.cpp"',
				directory + "/Observer.cpp",
				"-o",
				executable
			]) != 0)
				throw "standard integer observer failed to compile";
			observe(new sys.io.Process(timeout, ["30", executable]), expected, optimization);
			Sys.println("CPP_STANDARD_INT:" + optimization + ":PASS");
		}
		authoredOverride();
		Sys.println("CPP_STANDARD_INT:PASS");
	}

	/** A source-owned Std.int body must execute even when its signature matches the standard operation. */
	static function authoredOverride():Void {
		final source = "class Main { static function main():Void { if (Std.int(17.875) != 73) throw 'lost authored Std.int'; } }";
		final replacement = "class Std { public static function int(value:Float):Int { return 73; } }";
		final modules = [
			new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx")),
			new ResolvedModule("Std", "Std.hx", ParserStage.parse(replacement, "Std.hx"))
		];
		final index = TyperIndex.build(modules);
		final program = new MacroExpandedProgram([for (module in modules) TyperStage.typeResolvedModule(module, index)], false);
		final result = CppTargetCore.emit(program, new BackendContext(".tmp/cpp-standard-int-override", null, "Main", true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "authored Std override requires a native executable";
		observe(new sys.io.Process(result.entryPath, []), "", "authored override");
		Sys.println("CPP_STANDARD_INT:authored-override:PASS");
	}

	/** Output, stderr and process success must agree; sanitizer failures cannot count as matching output. */
	static function observe(process:sys.io.Process, expected:String, context:String):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected || stderr != "")
			throw "standard integer conversion differs at " + context + ": " + stdout + stderr;
	}
}
