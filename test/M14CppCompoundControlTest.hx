/** Native execution and forced collection must preserve saved compound-update values. */
class M14CppCompoundControlTest {
	public static function run():Void {
		final root = "test/oracle/compound_assignment_control_seed";
		observe(new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]));
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final output = ".tmp/cpp-compound-control";
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new backend.BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "compound control requires a native executable";
		observe(new sys.io.Process(result.entryPath, []));
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "compound control changed typed source";
		CppManagedAssertionFixture.sanitizers(output, "CPP_COMPOUND_CONTROL");
		Sys.println("CPP_COMPOUND_CONTROL:PASS");
	}

	/** Authored assertions fail the process; successful execution produces no output. */
	static function observe(process:sys.io.Process):Void {
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout.length != 0 || stderr.length != 0)
			throw "compound control assertions failed: " + stdout + stderr;
	}
}
