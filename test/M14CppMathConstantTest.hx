import backend.cpp.CppManagedRootedExpression;
import backend.cpp.CppManagedStaticStorage;
import backend.cpp.CppTypedProgramProjection;

/** Native standard constants use exact declarations instead of ordinary extern storage. */
class M14CppMathConstantTest {
	static function rejects(action:Void->Void, expected:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(expected) < 0)
				throw failure;
			return;
		}
		throw "Math constant accepted invalid ownership: " + expected;
	}

	static function main():Void {
		final root = "test/oracle/cpp_math_constant_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Math", "shadows.Math"]});
		final revisions = fixture.modules.map(module -> CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity());
		final prepared = CppResolvedFixture.prepare(fixture);
		final program = new CppTypedProgramProjection(prepared);
		final storage = new CppManagedStaticStorage(program, "hxhx_statics_test");
		final owner = program.requireClass(program.requireClassIdentity("Main"));
		final initializer = owner.getFieldInitializers().filter(field -> field.getField().getName() == "pi")[0];
		final expression = initializer.getExpression();
		final occurrence = initializer.findField(expression);
		if (occurrence == null || storage.constantValue(occurrence) == null)
			throw "Math fixture lost its actual standard constant";
		final reader = new CppManagedRootedExpression({
			owner: FieldInitializer(initializer),
			statics: storage,
			heap: "heap",
			temporaryPrefix: "hxhx_value_math_test_",
			resolve: _ -> throw "Math fixture has no closure"
		});
		final copied = switch expression {
			case EField(receiver, name): HxExpr.EField(receiver, name);
			case _: throw "Math alias lost its field expression";
		};
		rejects(() -> reader.render(copied, "result", ""), "absent");
		rejects(() -> storage.member(occurrence, true), "exact field");
		// A separate same-shaped declaration cannot borrow the real standard field object.
		final foreign = new ResolvedModule("Math", "Math.hx", ParserStage.parse("extern class Math { static var PI(default, null):Float; }", "Math.hx"));
		final other = new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(foreign, TyperIndex.build([foreign]))], false));
		rejects(() -> backend.cpp.CppManagedMathConstant.render(other, occurrence), "exact declaration");
		final method = owner.getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getDeclaration()) == "main")[0];
		final authored = HxFunctionDecl.getBody(method.requireSemanticDeclaration().getSourceDeclaration());
		authored.push(HxStmt.SReturn(HxExpr.EInt(99), HxPos.unknown()));
		rejects(() -> storage.constantValue(occurrence), "revision mismatch");
		authored.pop();
		reader.render(expression, "result", "");
		Sys.println("CPP_MATH_CONSTANT_OWNERSHIP:PASS");
		final output = ".tmp/cpp-math-constants";
		final result = backend.cpp.CppTargetCore.emit(prepared, new backend.BackendContext(output, null, "Main", true, fixture.defines));
		if (!result.builtExecutable)
			throw "Math constant program did not build";
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "Math constant emission changed authored source";
		execute(result.entryPath, "");
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		for (optimization in ["-O0", "-O2"]) {
			final binary = output + "/observer" + optimization;
			if (Sys.command("c++", [
				"-std=c++17",
				optimization,
				"-Wall",
				"-Wextra",
				"-Werror",
				"-g",
				"-fno-omit-frame-pointer",
				"-fsanitize=address,undefined",
				"-fno-sanitize-recover=all",
				"-I" + output + "/src",
				root + "/Observe.cpp",
				"-o",
				binary
			]) != 0)
				throw "Math constant observer failed to compile";
			execute(binary, expected + expected);
			Sys.println("CPP_MATH_CONSTANT:PASS " + optimization);
		}
	}

	/** Exact output and empty stderr prevent a sanitizer warning from counting as success. */
	static function execute(binary:String, expected:String):Void {
		final child = new sys.io.Process(binary, []);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final status = child.exitCode();
		child.close();
		if (status != 0 || stdout != expected || stderr != "")
			throw "Math constant runtime differs: " + status + " " + stdout + stderr;
	}
}
