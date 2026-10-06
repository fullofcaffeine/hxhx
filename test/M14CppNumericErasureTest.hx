/** Distinguish typed Float transport from opaque erasure in complete authored function bodies. */
class M14CppNumericErasureTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_numeric_erasure_seed",
			mainModule: "NumericTransport",
			requiredModules: ["Any"]
		});
		final expanded = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final program = new backend.cpp.CppTypedProgramProjection(expanded);
		final classes = new backend.cpp.CppManagedClassStorage(program);
		final owner = program.requireClass(program.requireClassIdentity("NumericTransport"));
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
		final output = ".tmp/cpp-numeric-erasure";
		sys.FileSystem.createDirectory(output);
		new backend.cpp.CppManagedRuntime().publish(output);
		sys.io.File.saveContent(output
			+ "/Generated.hpp", '#include "ManagedCallable.hpp"\n#include "ManagedThrow.hpp"\n'
			+ classes.render()
			+ "\n"
			+ body);
		program.assertCurrent();
		CppManagedAssertionFixture.sanitizers(output, "CPP_NUMERIC_ERASURE", "test/cpp_managed_heap/NumericErasureObserver.cpp", "Generated.hpp");
		Sys.println("CPP_NUMERIC_ERASURE:PASS");
	}
}
