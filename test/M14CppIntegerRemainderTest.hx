/** Verify exact native remainder, typed exceptions, nullable operands and collecting execution. */
class M14CppIntegerRemainderTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_integer_remainder_seed",
			mainModule: "Main",
			requiredModules: ["haxe.Exception", "haxe.ValueException"]
		});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final integer = TyType.fromHintText("Int");
		for (hint in ["Float", "Bool", "String", "Dynamic", "Null<Float>", "haxe.Int64"]) {
			for (reverse in [false, true]) {
				var rejected = false;
				try {
					backend.cpp.CppManagedInteger.resultType("%", reverse ? TyType.fromHintText(hint) : integer, reverse ? integer : TyType.fromHintText(hint));
				} catch (error:haxe.Exception) {
					rejected = error.message.indexOf("requires exact Int or nullable Int operands") >= 0;
				}
				if (!rejected)
					throw "remainder admitted an unsupported operand type";
			}
		}
		var requiresContext = false;
		try {
			backend.cpp.CppManagedInteger.compute("%", integer, integer, "left", "right", "result", "negative_", "");
		} catch (error:haxe.Exception) {
			requiresContext = error.message == "managed integer remainder requires rooted exception context";
		}
		if (!requiresContext)
			throw "remainder bypassed its required exception context";
		final output = ".tmp/cpp-integer-remainder";
		final program = CppResolvedFixture.prepare(fixture);
		final result = backend.cpp.CppTargetCore.emit(program, new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		for (i in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[i]).getCanonicalIdentity() != revisions[i])
				throw "remainder emission changed authored source";
		program.assertTypedBodyRevisionsCurrent();
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "native remainder assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_INTEGER_REMAINDER", "test/cpp_managed_heap/StringCatchObserver.cpp");
		Sys.println("CPP_INTEGER_REMAINDER:PASS");
	}
}
