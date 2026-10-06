import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Native execution must preserve initializer functions and their captured state. */
class M14SourceFieldInitializerNativeTest {
	static function main():Void {
		final root = "test/oracle/source_field_initializer_control_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final fields = typed.getTypedClasses()[0].getFieldInitializers();
		final revisions = [
			for (field in fields)
				CompilerTypedTreeRevision.expression(field.getField().getCanonicalKey(), field.getExpression())
		];
		final context = new BackendContext(".tmp/source-field-initializer-control", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false), context);
		if (!result.builtExecutable)
			throw "initializer fixture requires a native executable";
		for (index in 0...fields.length)
			if (CompilerTypedTreeRevision.expression(fields[index].getField().getCanonicalKey(), fields[index].getExpression()) != revisions[index])
				throw "native emission changed typed field source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "initializer native behavior differs: " + stdout + stderr;
		Sys.println("SOURCE_FIELD_INITIALIZER_NATIVE:PASS");
	}
}
