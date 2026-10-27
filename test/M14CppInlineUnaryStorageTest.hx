import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare exact unary writeback and receiver effects with independent upstream and native observers. */
class M14CppInlineUnaryStorageTest {
	static function main():Void {
		final root = "test/fixtures/cpp_inline_unary_storage_seed";
		final upstream = new sys.io.Process("haxe", ["-cp", root, "-main", "OracleMain", "--interp"]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || stderr != "" || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "upstream inline unary storage differs from the independent expectation: " + stdout + stderr;
		Sys.println("CPP_INLINE_UNARY_STORAGE:UPSTREAM:PASS");
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Array"]});
		Sys.println("CPP_INLINE_UNARY_STORAGE:LOADED modules=" + fixture.modules.length);
		final typed = fixture.main;
		final before = CompilerTypedModuleRevision.fromTypedModule(typed).implementationRevision;
		final program = CppResolvedFixture.prepare(fixture);
		Sys.println("CPP_INLINE_UNARY_STORAGE:PREPARED");
		final output = ".tmp/cpp-inline-unary-storage";
		CppTargetCore.emit(program, new BackendContext(output, output + "/Main.cpp", "Main", false, fixture.defines));
		if (CompilerTypedModuleRevision.fromTypedModule(typed).implementationRevision != before)
			throw "inline unary preparation changed the original typed module";
		Sys.println("CPP_INLINE_UNARY_STORAGE:EMITTED");
		M14CppManagedStartupExecutionTest.observeFixture({
			sourceRoot: root,
			output: output,
			observer: "test/cpp_managed_heap/InlineUnaryStorageObserver.cpp"
		});
		Sys.println("CPP_INLINE_UNARY_STORAGE:PASS");
	}
}
