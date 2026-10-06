/**
	Exercise the erased operation with upstream scalar expectations and native lifetime observers.
	The complete source program remains a separate requirement in M14CppDynamicEqualityTest.
 */
class M14CppDynamicEqualityValuesTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_dynamic_equality_seed",
			mainModule: "Compare",
			requiredModules: ["Any"]
		});
		final program = new backend.cpp.CppTypedProgramProjection(CppResolvedFixture.prepare(fixture));
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final owner = program.requireClass(program.requireClassIdentity("Compare"));
		final inputs:Array<backend.cpp.CppManagedProgramEmitter.CppManagedProgramFunction> = [
			for (projection in owner.getFunctions()) {
				final name = projection.requireSemanticDeclaration().getSignature().getName();
				{
					projection: projection,
					rootSymbol: "generated_" + name,
					symbolPrefix: "hxhx_function_" + name
				};
			}
		];
		final body = new backend.cpp.CppManagedProgramEmitter({
			functions: inputs,
			output: [],
			classes: classes,
			casts: classes.casts,
			defaultValue: type -> backend.cpp.CppManagedStaticDefault.render(program, type)
		}).render();
		final output = ".tmp/cpp-dynamic-equality-values";
		sys.FileSystem.createDirectory(output);
		new backend.cpp.CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output + "/Generated.hpp", '#include "ManagedCallable.hpp"\n' + classes.render() + "\n" + body);
		program.assertCurrent();
		CppManagedAssertionFixture.sanitizers(output, "CPP_DYNAMIC_EQUALITY_VALUES", "test/cpp_managed_heap/DynamicEqualityObserver.cpp", "Generated.hpp");
		Sys.println("CPP_DYNAMIC_EQUALITY_VALUES:PASS");
	}
}
