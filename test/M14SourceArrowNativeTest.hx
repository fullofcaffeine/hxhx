import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Execute the upstream-checked arrow assertions through the production managed C++ target. */
class M14SourceArrowNativeTest {
	static function main():Void {
		final started = Sys.cpuTime();
		final path = "test/oracle/source_arrow_return_seed/ArrowExecution.hx";
		final module = new ResolvedModule("ArrowExecution", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		Sys.println("SOURCE_ARROW_NATIVE:typed:cpu_seconds=" + (Sys.cpuTime() - started));
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(".tmp/source-arrow-native", null, "ArrowExecution", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "arrow assertions require a native executable";
		Sys.println("SOURCE_ARROW_NATIVE:built:cpu_seconds=" + (Sys.cpuTime() - started));
		final child = new sys.io.Process(result.entryPath, []);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stdout.length != 0 || stderr.length != 0)
			throw "native arrow assertions failed: " + stdout + stderr;
		Sys.println("SOURCE_ARROW_NATIVE:PASS");
	}
}
