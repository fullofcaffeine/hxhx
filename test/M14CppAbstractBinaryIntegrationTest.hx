import backend.BackendContext;
import backend.BackendRegistry;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Builds and executes the repo-owned abstract-binary contract through C++. **/
class M14CppAbstractBinaryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Locate the authored entry after shared preparation, before native symbol numbering. */
	static function mainFunction(program:MacroExpandedProgram):TypedFunction {
		for (module in program.getTypedModules())
			if (module.getSourceOrigin().sourceModulePath == "Main")
				for (owner in module.getTypedClasses())
					if (HxClassDecl.getName(owner.getSourceDeclaration()) == "Main")
						for (fn in owner.getFunctions())
							if (HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")
								return fn;
		throw "abstract-binary fixture lost its exact Main.main body";
	}

	static function expressionsIn(value:TypedExpr):Array<TypedExpr> {
		final result = [value];
		for (child in value.getExpressions())
			for (nested in expressionsIn(child))
				result.push(nested);
		return result;
	}

	/** Method spelling alone is insufficient: retain the exact source module and class owner. */
	static function selectedCalls(expressions:Array<TypedExpr>, owner:String, method:String):Array<TypedExpr> {
		return expressions.filter(function(expression) {
			final declaration = expression.getDeclaration();
			return expression.getTag() == Call
				&& declaration != null
				&& declaration.getModulePath() == "Main"
				&& declaration.getOwner().getCanonicalName() == owner
				&& declaration.getSignature().getName() == method;
		});
	}

	static function initializer(main:TypedFunction, name:String):TypedExpr {
		for (statement in main.getBody().getStatements())
			if (statement.getNames().length > 0 && statement.getNames()[0] == name && statement.getExpressions().length == 1) {
				var value = statement.getExpressions()[0];
				while (value.getTag() == Parenthesized)
					value = value.getExpressions()[0];
				return value;
			}
		throw "abstract-binary fixture lost initializer " + name;
	}

	static function temporaryBinding(value:TypedExpr):TyLocalBinding {
		final bindings = value.getLocalBindings();
		assertTrue(value.getTag() == Temporary
			&& value.getExpressions().length == 1
			&& bindings.length == 1
			&& bindings[0].getIdentity().isCompilerTemporary(),
			"binary operand lost its exact compiler temporary");
		return bindings[0];
	}

	static function assertBindingRead(value:TypedExpr, binding:TyLocalBinding):Void {
		while (value.getTag() == Parenthesized || value.isRepresentationPreservingCast())
			value = value.getExpressions()[0];
		assertTrue(value.getTag() == LocalRead
			&& value.getLocalBindings().length == 1
			&& value.getLocalBindings()[0].getIdentity().equals(binding.getIdentity()),
			"binary call or writeback changed its captured operand");
	}

	/** Capture left then right once; commutative dispatch may reverse only the resulting argument reads. */
	static function assertOrderedCall(main:TypedFunction, name:String, owner:String, method:String, reverse:Bool = false):Void {
		final value = initializer(main, name);
		final children = value.getExpressions();
		assertTrue(value.getTag() == Block && children.length == 3, "binary operation lost its ordered capture/call block: " + name);
		final left = temporaryBinding(children[0]);
		final right = temporaryBinding(children[1]);
		final calls = selectedCalls(expressionsIn(children[2]), owner, method);
		assertTrue(calls.length == 1 && calls[0].getExpressions().length == 3, "binary operation lost its selected two-argument call: " + name);
		final arguments = calls[0].getExpressions();
		assertBindingRead(arguments[1], reverse ? right : left);
		assertBindingRead(arguments[2], reverse ? left : right);
		if (owner == "Main.Parcel")
			assertTrue(children[2].isRepresentationPreservingCast(), "class-backed operator result lost its original object storage");
		if (reverse) {
			assertTrue(selectedCalls(expressionsIn(children[0]), "Main.EventLog", "text").length == 1,
				"commutative source-left effect moved out of its first capture");
			assertTrue(selectedCalls(expressionsIn(children[1]), "Main", "ticket").length == 1,
				"commutative source-right effect moved out of its second capture");
		}
	}

	/** Indexed fallback must read and write the same captured array and index, not a copied place. */
	static function assertIndexedWriteback(main:TypedFunction):Void {
		final value = initializer(main, "fallbackResult");
		final children = value.getExpressions();
		assertTrue(value.getTag() == Block && children.length == 7, "indexed fallback lost its explicit read/call/write schedule");
		final array = temporaryBinding(children[0]);
		final index = temporaryBinding(children[1]);
		final capturedArray = children[0].getExpressions()[0];
		assertTrue(capturedArray.getTag() == LocalRead
			&& capturedArray.getLocalBindings().length == 1
			&& capturedArray.getLocalBindings()[0].getSourceName() == "fallbackValues",
			"indexed fallback did not capture the original array");
		assertTrue(selectedCalls(expressionsIn(value), "Main", "chooseIndex").length == 1, "indexed fallback repeated its index effect");
		final accesses = expressionsIn(value).filter(function(expression) return expression.getTag() == ArrayAccess);
		assertTrue(accesses.length == 2, "indexed fallback lost its paired array read and write");
		for (access in accesses) {
			assertBindingRead(access.getExpressions()[0], array);
			assertBindingRead(access.getExpressions()[1], index);
		}
		assertTrue(children[5].getTag() == Assign && children[5].getExpressions()[0].getTag() == ArrayAccess,
			"indexed fallback omitted writeback into the original place");
		final result = temporaryBinding(children[4]);
		assertBindingRead(children[5].getExpressions()[1], result);
		assertBindingRead(children[6], result);
	}

	/** Preserve operator selection and storage assertions independently of emitted function names. */
	static function assertPreparedOperators(program:MacroExpandedProgram):Void {
		final main = mainFunction(program);
		final expressions = new Array<TypedExpr>();
		function statement(value:TypedStmt):Void {
			for (expression in value.getExpressions())
				for (nested in expressionsIn(expression))
					expressions.push(nested);
			for (child in value.getStatements())
				statement(child);
		}
		for (child in main.getBody().getStatements())
			statement(child);
		for (helper in [
			{owner: "Ticket", method: "mergeArbitrarily", count: 1},
			{owner: "Ticket", method: "decorateArbitrarily", count: 2},
			{owner: "Ticket", method: "trimArbitrarily", count: 1},
			{owner: "Ticket", method: "advanceArbitrarily", count: 2},
			{owner: "Parcel", method: "uniteArbitrarily", count: 1},
			{owner: "Parcel", method: "enlargeArbitrarily", count: 1},
			{owner: "Parcel", method: "enlargeInPlaceArbitrarily", count: 1},
			{owner: "Distance", method: "reduceArbitrarily", count: 1},
			{owner: "Distance", method: "labelArbitrarily", count: 1},
			{owner: "FallbackDistance", method: "addArbitrarily", count: 1}
		])
			assertTrue(selectedCalls(expressions, "Main." + helper.owner, helper.method).length == helper.count,
				"binary operator lost its exact arbitrary-name helper: "
				+ helper.owner
				+ "."
				+ helper.method);
		assertTrue(selectedCalls(expressions, "Main.Distance", "mutateArbitrarily").length == 0,
			"inline instance compound helper survived for backend reinterpretation");
		assertOrderedCall(main, "merged", "Main.Ticket", "mergeArbitrarily");
		assertOrderedCall(main, "reversed", "Main.Ticket", "decorateArbitrarily", true);
		assertOrderedCall(main, "united", "Main.Parcel", "uniteArbitrarily");
		assertOrderedCall(main, "enlarged", "Main.Parcel", "enlargeArbitrarily");
		assertOrderedCall(main, "parcelResult", "Main.Parcel", "enlargeInPlaceArbitrarily");
		assertIndexedWriteback(main);
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
		final process = new sys.io.Process(command, arguments == null ? [] : arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	/** Every original output and effect must survive forced collection in both sanitizer profiles. */
	static function assertSanitized(root:String, expected:String):Void {
		// EventLog.value is a by-value String. Only the standard provider graph remains managed after main.
		File.copy("test/cpp_managed_heap/StandardStringObserver.cpp", root + "/Observer.cpp");
		final compiler = Sys.getEnv("CXX") == null ? "clang++" : Sys.getEnv("CXX");
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		for (optimization in ["-O0", "-O2"]) {
			final executable = root + "/observer" + optimization;
			final compiled = Sys.command(timeout, [
				"90",
				compiler,
				"-std=c++17",
				optimization,
				"-g1",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-fno-sanitize-recover=all",
				'-DHXHX_LOCAL_PROGRAM="src/Main.cpp"',
				root + "/Observer.cpp",
				"-o",
				executable
			]);
			assertTrue(compiled == 0, "abstract-binary sanitizer compilation failed: " + optimization + " exit=" + compiled);
			final executed = commandOutput(timeout, ["30", executable]);
			assertTrue(executed.code == 0 && executed.stderr == "" && executed.stdout == expected,
				"abstract-binary sanitizer behavior differs: "
				+ optimization
				+ " exit="
				+ executed.code
				+ "\n"
				+ executed.stdout
				+ executed.stderr);
			Sys.println("CPP_ABSTRACT_BINARY:SANITIZERS:" + optimization + ":PASS");
		}
	}

	static function main():Void {
		final sourceRoot = "test/oracle/cpp_abstract_binary_operator_seed/src";
		final expected = File.getContent("test/oracle/cpp_abstract_binary_operator_seed/expected.stdout");
		final upstream = commandOutput("haxe", ["-cp", sourceRoot, "--run", "Main"]);
		assertTrue(upstream.code == 0 && upstream.stderr == "" && upstream.stdout == expected,
			"upstream abstract-binary contract differs: " + upstream.stdout + upstream.stderr);
		Sys.println("CPP_ABSTRACT_BINARY:UPSTREAM:PASS");
		// Calls and output conversions need their real declarations. Production
		// preparation also preserves the exact selected operator and source effects.
		final fixture = CppResolvedFixture.load({sourceRoot: sourceRoot, mainModule: "Main", requiredModules: ["Std", "Sys", "Array"]});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		Sys.println("CPP_ABSTRACT_BINARY:LOADED modules=" + fixture.modules.length);
		final program = CppResolvedFixture.prepare(fixture);
		assertPreparedOperators(program);
		Sys.println("CPP_ABSTRACT_BINARY:PREPARED");

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_abstract_binary"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		final context = new BackendContext(root, null, "Main", true, fixture.defines);
		final result = BackendRegistry.createForTarget("cpp-native").emit(program, context);
		assertTrue(result.builtExecutable, "focused abstract-binary C++ artifact did not build");
		for (index in 0...fixture.modules.length)
			assertTrue(revisions[index] == CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity(),
				"abstract-binary preparation changed an authored typed module");
		final cppCore = File.getContent("packages/hxhx-core/src/backend/cpp/CppTargetCore.hx");
		for (legacyOwner in [
			"primitiveStringAbstractBinaryOpExpr",
			"classBackedAbstractBinaryOpMethod",
			"isPrimitiveStringRepeatHelper"
		])
			assertTrue(cppCore.indexOf(legacyOwner) < 0, "legacy target-side abstract binary owner survived: " + legacyOwner);

		final executed = commandOutput(result.entryPath);
		assertTrue(executed.code == 0 && executed.stderr == "", "focused abstract-binary executable failed: " + executed.stderr);
		assertTrue(executed.stdout == expected, "unexpected focused abstract-binary stdout:\n" + executed.stdout);
		assertSanitized(root, expected);
		Sys.println("CPP_ABSTRACT_BINARY:PASS");
		deleteRecursive(root);
	}
}
