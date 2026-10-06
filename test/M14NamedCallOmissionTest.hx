import backend.cpp.CppTargetCore;
import backend.BackendContext;

/** A named call must skip a defaulted parameter when its operand belongs to the required suffix. */
class M14NamedCallOmissionTest {
	static function main():Void {
		final root = "test/oracle/named_call_omission_seed";
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		if (Sys.command(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]) != 0)
			throw "upstream named omission assertions failed";
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final output = ".tmp/cpp-named-call-omission";
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "native named omission assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "NAMED_CALL_OMISSION");
		Sys.println("NAMED_CALL_OMISSION:PASS");
	}
}
