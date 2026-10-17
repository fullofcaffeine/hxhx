/** Check instance identity through authored Haxe and a collecting native runtime. */
class M14CppInstanceEqualityTest {
	static function main():Void {
		final path = "test/oracle/cpp_instance_equality_seed/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final casts = new backend.cpp.CppManagedCastPlan(program);
		final base = TyType.nominal(new TyNominalTypeId("Main.Base"), []);
		final child = TyType.nominal(new TyNominalTypeId("Main.Child"), []);
		if (!backend.cpp.CppManagedClassEquality.selectsInstances("==", base, child, classes, casts)
			|| !backend.cpp.CppManagedClassEquality.selectsInstances("!=", child, base, classes, casts)
			|| backend.cpp.CppManagedClassEquality.selectsInstances("<", base, base, classes, casts))
			throw "instance comparison lost its exact equality contract";
		for (wrong in ["Int", "Float", "Bool", "String", "Dynamic", "Null<Int>"])
			if (backend.cpp.CppManagedClassEquality.selectsInstances("==", base, TyType.fromHintText(wrong), classes, casts))
				throw "instance comparison accepted unrelated storage: " + wrong;
		final output = ".tmp/cpp-instance-equality";
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "instance equality assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_INSTANCE_EQUALITY");
		Sys.println("CPP_INSTANCE_EQUALITY:PASS");
	}
}
