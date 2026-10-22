/** Preserve opaque-value comparisons through the real Any declaration and managed native storage. */
class M14CppAnyInstanceEqualityTest {
	static function main():Void {
		final root = "test/oracle/cpp_any_instance_equality_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Any"]});
		final lowered = TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index);
		final expanded = new MacroExpandedProgram(lowered, false);
		final program = new backend.cpp.CppTypedProgramProjection(expanded);
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final casts = new backend.cpp.CppManagedCastPlan(program);
		final opaque = TyType.nominal(new TyNominalTypeId("Any"), []);
		final token = TyType.nominal(new TyNominalTypeId("Main.Token"), []);
		if (!casts.representationType(opaque).isDynamic()
			|| !backend.cpp.CppManagedClassEquality.selectsOpaqueInstances("==", opaque, token, classes, casts)
			|| !backend.cpp.CppManagedClassEquality.selectsOpaqueInstances("!=", token, opaque, classes, casts))
			throw "opaque comparison lost its declared storage or operand order";
		for (wrong in ["Int", "Float", "Bool", "String"])
			if (backend.cpp.CppManagedClassEquality.selectsOpaqueInstances("==", opaque, TyType.fromHintText(wrong), classes, casts))
				throw "opaque comparison admitted a non-instance counterpart: " + wrong;
		if (backend.cpp.CppManagedClassEquality.selectsOpaqueInstances("==", opaque, opaque, classes, casts)
			|| backend.cpp.CppManagedClassEquality.selectsOpaqueInstances("<", opaque, token, classes, casts)
			|| backend.cpp.CppManagedClassEquality.selectsInstances("==", opaque, token, classes, casts))
			throw "opaque comparison changed ordinary reference admission";
		var comparisons = 0;
		var overrides = 0;
		function expression(value:TypedExpr):Void {
			final declaration = value.getDeclaration();
			if (value.getTag() == TypedExpr.TypedExprTag.Call
				&& declaration != null
				&& declaration.getOwner().getCanonicalName() == "Main.NeverEqual"
				&& declaration.getSignature().getName() == "same")
				overrides++;
			if (value.getTag() == TypedExpr.TypedExprTag.Binary && (value.getTexts()[0] == "==" || value.getTexts()[0] == "!=")) {
				final children = value.getExpressions();
				if (backend.cpp.CppManagedClassEquality.selectsOpaqueInstances(value.getTexts()[0], children[0].getType(), children[1].getType(), classes,
					casts))
					comparisons++;
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (item in value.getExpressions())
				expression(item);
			for (child in value.getStatements())
				statement(child);
		}
		for (module in lowered)
			for (owner in module.getTypedClasses())
				for (method in owner.getFunctions())
					if (method.getOwnerName() == "Main")
						for (item in method.getBody().getStatements())
							statement(item);
		if (comparisons != 7 || overrides != 1)
			throw "opaque source comparisons did not survive ordinary typed lowering: " + comparisons;
		final output = ".tmp/cpp-any-instance-equality";
		final result = backend.cpp.CppTargetCore.emit(expanded, new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "opaque instance fixture did not produce a native executable";
		if (Sys.command(result.entryPath, []) != 0)
			throw "opaque instance assertions failed";
		// Select the native observer's entry by its exact declaration, not a guessed symbol.
		final plan = new backend.cpp.CppManagedProgramPlan(program, "Main");
		final owner = fixture.index.getByFullName("Main");
		final identity = owner.declarationForSignature(owner.staticMethod("compareFailure")).getIdentity().getCanonicalKey();
		final target = @:privateAccess plan.emitter.resolve(identity);
		sys.io.File.saveContent(output
			+ "/Bindings.hpp", "#define HXHX_COMPARE_FAILURE "
			+ backend.cpp.CppManagedStaticTarget.sourceSymbol(target)
			+ "\n");
		CppManagedAssertionFixture.sanitizers(output, "CPP_ANY_INSTANCE_EQUALITY", "test/cpp_managed_heap/AnyInstanceEqualityObserver.cpp");
		Sys.println("CPP_ANY_INSTANCE_EQUALITY:PASS");
	}
}
