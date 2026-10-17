/** Run the complete authored object conversion contract with the real standard-library closure. */
class M14CppObjectStringTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_object_string_seed",
			mainModule: "Main",
			requiredModules: ["Std", "haxe.ValueException"]
		});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/cpp-object-string";
		final result = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "object string conversion changed its authored source";
		if (!result.builtExecutable)
			throw "object string conversion did not build its native program";
		final process = new sys.io.Process(result.entryPath, []);
		final outputBytes = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0 || errors != "" || outputBytes != sys.io.File.getContent("test/oracle/cpp_object_string_seed/expected.cpp.stdout"))
			throw "object string conversion differs from upstream: " + status + " " + errors + " output=" + outputBytes;
		Sys.println("CPP_OBJECT_STRING:PASS");
	}
}
