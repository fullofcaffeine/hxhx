import backend.cpp.CppManagedBoolean.supportsCondition;
import backend.cpp.CppManagedBoolean.conditionValue;

/** Null selects false control branches while the original nullable value remains unchanged. */
class M14CppNullableBooleanTest {
	static function main():Void {
		for (type in [
			TyType.fromHintText("Dynamic"),
			TyType.fromHintText("Int"),
			TyType.fromHintText("String")
		]) {
			if (supportsCondition(type))
				throw "unrelated condition admitted";
			var rejected = false;
			try
				conditionValue(type, "value")
			catch (failure:haxe.Exception) {
				if (failure.message != "managed condition requires Bool or nullable Bool")
					throw failure;
				rejected = true;
			}
			if (!rejected)
				throw "unrelated condition rendered";
			for (expression in [
				HxExpr.EBinop("&&", HxExpr.EBool(false), HxExpr.EIdent("invalid")),
				HxExpr.EUnop(LogicalNot, Prefix, HxExpr.EIdent("invalid")),
				HxExpr.ETernary(HxExpr.EBool(true), HxExpr.EBool(true), HxExpr.EIdent("invalid"))
			]) {
				final valueType = (value:HxExpr) -> switch value {
					case EBool(_): TyType.fromHintText("Bool");
					case _: type;
				};
				// Both validation and emission must inspect even a runtime-skipped wrong-type leaf.
				for (emit in [false, true]) {
					var failed = false;
					try {
						if (emit)
							backend.cpp.CppManagedBoolean.renderCondition(expression, {
								heap: "heap",
								prefix: "test_",
								valueType: valueType,
								requireExpression: _ -> {},
								renderValue: (_, _, _) -> []
							});
						else
							backend.cpp.CppManagedBoolean.requireCondition(expression, valueType, _ -> {});
					} catch (failure:haxe.Exception) {
						if (failure.message != "managed condition requires Bool or nullable Bool")
							throw failure;
						failed = true;
					}
					if (!failed)
						throw "nested condition admitted an unrelated operand";
				}
			}
		}
		final path = "test/oracle/cpp_nullable_boolean_seed/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final output = ".tmp/cpp-nullable-boolean";
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "nullable Boolean assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_NULLABLE_BOOLEAN");
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/oracle/cpp_nullable_logical_throw_seed",
			output: ".tmp/cpp-nullable-logical-throw",
			observer: "test/cpp_managed_heap/NullableLogicalThrowObserver.cpp"
		});
		Sys.println("CPP_NULLABLE_BOOLEAN:PASS");
	}
}
