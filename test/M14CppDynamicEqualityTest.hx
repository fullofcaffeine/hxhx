/** Compare erased values against independently observed Haxe 4.3.7 native C++ results. */
class M14CppDynamicEqualityTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_dynamic_equality_seed",
			mainModule: "Main",
			requiredModules: ["Main"]
		});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/cpp-dynamic-equality";
		final result = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "Dynamic equality emission changed its authored typed source";
		if (!result.builtExecutable)
			throw "Dynamic equality did not build an executable";
		final process = new sys.io.Process(result.entryPath, []);
		final actual = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0 || errors != "" || actual != sys.io.File.getContent("test/oracle/cpp_dynamic_equality_seed/expected.cpp.stdout"))
			throw "Dynamic equality differs from upstream native C++ observations: " + status + " " + errors;
		Sys.println("CPP_DYNAMIC_EQUALITY:PASS");
	}
}
