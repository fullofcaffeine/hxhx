import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe short-circuit side effects through the normal authored-source compilation path. */
class M14CppManagedBooleanTest {
	static function main():Void {
		final path = "test/oracle/cpp_boolean_effects_seed/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(".tmp/cpp-boolean-effects", null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "logical effects require native execution";
		if (Sys.command(result.entryPath, []) != 0)
			throw "logical effects assertions failed";
		Sys.println("CPP_BOOLEAN_EFFECTS:PASS");
	}
}
