import backend.BackendContext;
import backend.BackendRegistry;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds the focused Class<T>/Enum<T> runtime-metadata contract through C++. **/
class M14CppMetaCarrierErasureIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function countOccurrences(haystack:String, needle:String):Int {
		var count = 0;
		var offset = 0;
		while (true) {
			final found = haystack.indexOf(needle, offset);
			if (found < 0)
				return count;
			count++;
			offset = found + needle.length;
		}
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function commandOutput(command:String, ?arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", command].concat(arguments == null ? [] : arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = try process.exitCode() catch (error:haxe.Exception) {
			process.close();
			throw new haxe.Exception("metadata subprocess terminated: " + command + "\n" + stdout + stderr, error);
		};
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	/**
		The managed target erases physical templates while retaining generic source
		facts and distinct applied method layouts. Metadata erasure must not turn
		GenericBox<Int>.value into Dynamic or merge its application with Box<String>.
	 */
	static function typedContracts(source:MacroExpandedProgram):Void {
		final projection = new backend.cpp.CppTypedProgramProjection(source);
		final classes = new backend.cpp.CppManagedClassStorage(projection);
		final enums = new backend.cpp.CppManagedEnumDescriptors(projection);
		final box = projection.requireClass(projection.requireClassIdentity("Main.GenericBox"));
		final facts = box.requireSemanticFacts();
		final parameters = facts.getTypeParameterIds();
		final fields = facts.copyFields();
		assertTrue(parameters.length == 1
			&& fields.length == 1
			&& fields[0].name == "value"
			&& fields[0].semanticType.getTypeParameterIdentity().equals(parameters[0]),
			"generic declaration lost its exact field binder");
		final ints = classes.requireType(TyType.nominal(new TyNominalTypeId("Main.GenericBox"), [TyType.fromHintText("Int")]));
		final strings = classes.requireType(TyType.nominal(new TyNominalTypeId("Main.GenericBox"), [TyType.fromHintText("String")]));
		assertTrue(ints.symbol == strings.symbol
			&& ints.instanceSymbol != strings.instanceSymbol
			&& ints.fields[0].semanticType.getSemanticKey() == "primitive:Int"
			&& strings.fields[0].semanticType.getSemanticKey() == "primitive:String",
			"generic applications lost precise storage or shared public identity");
		final opaque = TyType.fromHintText("Dynamic");
		final classType = TyType.nominal(new TyNominalTypeId("Class"), [opaque]);
		final enumType = TyType.nominal(new TyNominalTypeId("Enum"), [opaque]);
		final valueType = projection.requireClass(projection.requireClassIdentity("Type.ValueType")).requireSemanticFacts();
		for (name in ["TClass", "TEnum"]) {
			final constructor = valueType.copyEnumConstructors().filter(entry -> entry.name == name)[0];
			switch constructor.member {
				case Callable(method):
					assertTrue(method.arguments.length == 1
						&& method.arguments[0].semanticType.getSemanticKey() == (name == "TClass" ? classType : enumType).getSemanticKey(),
						"ValueType lost its precise metadata parameter: "
						+ name);
				case _:
					throw "metadata constructor lost its payload: " + name;
			}
		}
		assertTrue(!classes.casts.permitsMetadataErasure(classType, enumType)
			&& !classes.casts.permitsMetadataErasure(enumType, classType),
			"metadata erasure mixed class and enum categories");
		final reflection = new backend.cpp.CppManagedReflection(projection, classes, enums);
		final typeOwner = projection.requireClass(projection.requireClassIdentity("Type"));
		for (name in [
			"getClass",
			"getEnum",
			"getClassName",
			"getEnumName",
			"resolveClass",
			"resolveEnum"
		]) {
			final declaration = typeOwner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == name)[0].requireSemanticDeclaration();
			reflection.select(declaration);
			var rejected = false;
			try
				reflection.resultType(declaration, [HxExpr.EInt(1)], _ -> TyType.fromHintText("Int"), new backend.cpp.CppManagedClassStorage(projection))
			catch (error:haxe.Exception) {
				rejected = error.message.indexOf("another caller descriptor plan") >= 0;
			}
			assertTrue(rejected, "reflection accepted another caller plan: " + name);
		}
		currentHandleQueries(source, projection, classType, enumType);
		Sys.println("CPP_META_CARRIER_TYPED:PASS");
		Sys.stdout().flush();
	}

	/** Standalone handle queries must still reject changed source outside synchronous program planning. */
	static function currentHandleQueries(source:MacroExpandedProgram, projection:backend.cpp.CppTypedProgramProjection, classType:TyType,
			enumType:TyType):Void {
		var body:Null<Array<HxStmt>> = null;
		for (module in source.getTypedModules())
			if (module.getSourceOrigin().sourceModulePath == "Main")
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
							body = HxFunctionDecl.getBody(fn.getSourceDeclaration());
		assertTrue(body != null, "metadata source has no main body");
		final queries:Array<{name:String, run:Void->Bool}> = [
			{name: "Class", run: () -> backend.cpp.CppManagedClassValueType.selects(projection, classType)},
			{name: "Enum", run: () -> backend.cpp.CppManagedEnumValueType.selects(projection, enumType)},
			{
				name: "EnumValue",
				run: () -> backend.cpp.CppManagedEnumValueType.selectsInstanceView(projection, TyType.nominal(new TyNominalTypeId("EnumValue"), []))
			}
		];
		for (query in queries)
			assertTrue(query.run(), "current core handle was not selected: " + query.name);
		body.push(HxStmt.SExpr(HxExpr.EInt(1), HxPos.unknown()));
		final failures = new Array<String>();
		for (query in queries) {
			var rejected = false;
			try
				query.run()
			catch (error:haxe.Exception) {
				rejected = error.message.indexOf("typed body revision mismatch") >= 0;
				if (!rejected)
					failures.push(error.message);
			}
			if (!rejected)
				failures.push("stale source accepted by " + query.name);
		}
		body.pop();
		assertTrue(failures.length == 0, failures.join("\n"));
		projection.assertCurrent();
	}

	static function main():Void {
		final expected = File.getContent("test/oracle/cpp_meta_carrier_erasure_seed/expected.stdout");
		final upstream = commandOutput("node_modules/.bin/haxe", [
			"-cp",
			"test/oracle/cpp_meta_carrier_erasure_seed/src",
			"-main",
			"Main",
			"--interp"
		]);
		assertTrue(upstream.code == 0 && upstream.stdout == expected && upstream.stderr == "",
			"upstream metadata contract differs: " + upstream.stdout + upstream.stderr);
		Sys.println("CPP_META_CARRIER_UPSTREAM:PASS");
		Sys.stdout().flush();
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_meta_carrier_erasure_seed/src",
			mainModule: "Main",
			requiredModules: ["Main", "Type", "Sys"]
		});
		final program = CppResolvedFixture.prepare(fixture);
		final revision = program.getTypedProgramRevision().getCanonicalIdentity();
		typedContracts(program);
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_meta_carrier_erasure"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, true, fixture.defines);
		final result = try BackendRegistry.createForTarget("cpp-native").emit(program, context) catch (error:haxe.Exception) {
			Sys.println(error.details());
			throw error;
		};
		assertTrue(result.builtExecutable, "focused C++ meta-carrier artifact did not build");
		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0 && executed.stderr == "", "focused C++ meta-carrier executable failed: " + executed.stderr);
		assertTrue(executed.stdout == expected, "unexpected focused C++ meta-carrier stdout:\n" + executed.stdout);
		Sys.println("CPP_META_CARRIER_NATIVE:PASS");
		Sys.stdout().flush();

		final generated = File.getContent(Path.join([root, "src", "Main.cpp"]));
		assertTrue(countOccurrences(generated, "struct Class {") == 0 && countOccurrences(generated, "struct Enum {") == 0,
			"managed metadata must reuse descriptors instead of allocating wrapper classes");
		for (identity in ["Main.GenericBox", "Main.MetaChoice"])
			assertTrue(countOccurrences(generated, backend.cpp.CppManagedText.quotedBytes(identity)) == 1,
				"managed metadata must declare exactly one identity: " + identity);
		assertTrue(generated.indexOf("template<typename T>\nstruct Class;") < 0, "C++ should not forward-declare Class as a template");
		assertTrue(generated.indexOf("template<typename T>\nstruct Enum;") < 0, "C++ should not forward-declare Enum as a template");
		assertTrue(generated.indexOf("Class<") < 0, "C++ should erase every Class<T> runtime carrier use");
		assertTrue(generated.indexOf("Enum<") < 0, "C++ should erase every Enum<T> runtime carrier use");
		assertTrue(generated.indexOf("TDynamic") < 0, "C++ should not invent a Dynamic template placeholder for erased metadata");
		assertTrue(generated.indexOf("T__fn") < 0, "C++ should not leak a function type parameter into an erased metadata carrier");
		assertTrue(generated.indexOf("__hxhx_make_shared_Class") < 0, "C++ should not emit a generic factory for the Class metadata carrier");
		assertTrue(generated.indexOf("__hxhx_make_shared_Enum") < 0, "C++ should not emit a generic factory for the Enum metadata carrier");
		final observer = Path.join([root, "src", "MetaReflectionObserver.cpp"]);
		File.copy("test/cpp_managed_heap/MetaReflectionObserver.cpp", observer);
		for (optimization in ["-O0", "-O2"]) {
			final binary = Path.join([root, "observer" + optimization]);
			final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
			final compiled = commandOutput(compiler, [
				"-std=c++17",
				optimization,
				"-g",
				"-Wall",
				"-Wextra",
				"-Werror",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				observer,
				"-o",
				binary
			]);
			assertTrue(compiled.code == 0 && compiled.stderr == "", "metadata observer did not compile: " + compiled.stdout + compiled.stderr);
			final observed = commandOutput(binary);
			assertTrue(observed.code == 0 && observed.stderr == "" && observed.stdout == expected,
				"metadata observer changed behavior or reported a sanitizer failure: " + observed.stdout + observed.stderr);
			Sys.println("CPP_META_CARRIER_OBSERVER:" + optimization + ":PASS");
			Sys.stdout().flush();
		}
		program.assertTypedBodyRevisionsCurrent();
		assertTrue(program.getTypedProgramRevision().getCanonicalIdentity() == revision, "metadata emission changed shared typed source");
		deleteRecursive(root);
	}
}
