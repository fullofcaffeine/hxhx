import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare the authored provider boundary with independently captured native output. */
class M14CppInt64TransportTest {
	static function main():Void {
		nullBoundary();
		final root = "test/oracle/cpp_int64_class_predicate_seed/transport";
		final expected = sys.io.File.getContent(root + "/expected.cpp.stdout");
		phase("resolve");
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["haxe.Int64", "Type", "Std", "Array"]});
		phase("declarations");
		final owner = fixture.index.getByFullName("haxe.Int64.NativeInt64");
		if (owner == null)
			throw "Int64 transport did not load its bundled storage declarations";
		for (name in ["box", "high", "low", "isValue"])
			backend.cpp.CppManagedInt64Box.requireDeclaration(owner.declarationForSignature(owner.staticMethod(name)));
		final declaration = owner.declarationForSignature(owner.staticMethod("box"));
		final arguments = declaration.getSignature().getArgs();
		final original = arguments[0];
		arguments[0] = TyType.fromHintText("Float");
		var rejected = false;
		try {
			backend.cpp.CppManagedInt64Box.requireDeclaration(declaration);
		} catch (failure:haxe.Exception) {
			rejected = failure.message.indexOf("exact required operands") >= 0;
		}
		arguments[0] = original;
		if (!rejected)
			throw "Int64 storage accepted a mutated signature";
		final program = CppResolvedFixture.prepare(fixture);
		phase("emit");
		final directory = ".tmp/cpp-int64-transport";
		final before = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		CppTargetCore.emit(program, new BackendContext(directory, null, "Main", true, false, fixture.defines));
		final after = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		if (before.join("\n") != after.join("\n"))
			throw "Int64 target changed its authored provider";
		sys.io.File.copy("test/cpp_managed_heap/Int64TransportObserver.cpp", directory + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			phase("compile " + optimization);
			final executable = directory + "/observer" + optimization;
			final compileCode = Sys.command(timeout, [
				"240",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-fno-sanitize-recover=all",
				'-DHXHX_LOCAL_PROGRAM="src/Main.cpp"',
				directory + "/Observer.cpp",
				"-o",
				executable
			]);
			if (compileCode != 0)
				throw "Int64 transport observer failed to compile: exit=" + compileCode;
			observe(new sys.io.Process(timeout, ["90", executable]), expected, optimization);
			Sys.println("CPP_INT64_TRANSPORT:" + optimization + ":PASS");
		}
		authoredOverride();
		Sys.println("CPP_INT64_TRANSPORT:PASS");
	}

	/** The new physical payload preserves existing null comparison before numeric admission. */
	static function nullBoundary():Void {
		final directory = ".tmp/cpp-int64-null-boundary";
		sys.FileSystem.createDirectory(directory);
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = directory + "/observer" + optimization;
			final compileCode = Sys.command(timeout, [
				"240",
				compiler,
				"-std=c++17",
				optimization,
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-fno-sanitize-recover=all",
				"-Ipackages/hxhx-core/runtime/cpp",
				"test/cpp_managed_heap/Int64NullBoundary.cpp",
				"-o",
				executable
			]);
			if (compileCode != 0)
				throw "Int64 null observer failed to compile: exit=" + compileCode;
			observe(new sys.io.Process(timeout, ["30", executable]), "", "null boundary " + optimization);
		}
		Sys.println("CPP_INT64_NULL_BOUNDARY:PASS");
	}

	/** Bounded phase markers distinguish provider loading, emission and native compilation. */
	static function phase(name:String):Void {
		Sys.println("CPP_INT64_TRANSPORT:PHASE " + name);
		Sys.stdout().flush();
	}

	/** A source replacement of the public provider must retain its body and classpath priority. */
	static function authoredOverride():Void {
		// Standard-library consumers need the complete Int64 declarations. Keep
		// that public contract and replace only one private helper with Haxe code.
		final source = sys.io.File.getContent("packages/hxhx-core/std/cpp/_std/haxe/Int64.hx");
		final signature = "static function isValue(value:Dynamic):Bool;";
		if (source.split(signature).length != 2)
			throw "Int64 override requires one exact helper declaration";
		final root = ".tmp/cpp-int64-override-source";
		sys.FileSystem.createDirectory(root + "/haxe");
		sys.io.File.copy("test/oracle/cpp_int64_class_predicate_seed/override/Main.hx", root + "/Main.hx");
		sys.io.File.saveContent(root + "/haxe/Int64.hx",
			StringTools.replace(source, signature, "static inline function isValue(value:Dynamic):Bool return false;"));
		final fixture = CppResolvedFixture.load({
			sourceRoot: root,
			mainModule: "Main",
			requiredModules: ["haxe.Int64", "Sys"]
		});
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new BackendContext(".tmp/cpp-int64-override", null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "authored Int64 override requires native execution";
		observe(new sys.io.Process(result.entryPath, []), "false\n", "authored override");
		Sys.println("CPP_INT64_TRANSPORT:authored-override:PASS");
	}

	/** Sanitizer diagnostics, failed processes and output mismatches are all failures. */
	static function observe(process:sys.io.Process, expected:String, context:String):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected || stderr != "")
			throw "Int64 transport differs at " + context + ": exit=" + code + " " + stdout + stderr;
	}
}
