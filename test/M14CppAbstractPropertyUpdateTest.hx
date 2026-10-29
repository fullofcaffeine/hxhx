import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare authored accessor effects with upstream and independent native sanitizer observations. */
class M14CppAbstractPropertyUpdateTest {
	static function main():Void {
		final root = "test/fixtures/cpp_abstract_property_update_seed";
		final upstream = new sys.io.Process("haxe", ["-cp", root, "--run", "OracleMain"]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || stderr != "" || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "upstream property update differs: " + stdout + stderr;
		final source = sys.io.File.getContent(root + "/Main.hx");
		final resolved = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final before = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules([typed], index), false);
		final output = ".tmp/cpp-abstract-property-update";
		CppTargetCore.emit(program, new BackendContext(output, output + "/Main.cpp", "Main", false, new haxe.ds.StringMap()));
		if (before != CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity())
			throw "property preparation changed its authored typed source";
		M14CppManagedStartupExecutionTest.observeFixture({
			sourceRoot: root,
			output: output,
			observer: "test/cpp_managed_heap/AbstractPropertyUpdateObserver.cpp"
		});
		Sys.println("CPP_ABSTRACT_PROPERTY_UPDATE:PASS");
	}
}
