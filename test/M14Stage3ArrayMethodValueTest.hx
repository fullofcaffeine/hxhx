import sys.io.File;

/** Compare saved runtime-backed methods with upstream, including aliases and effectful arguments. */
class M14Stage3ArrayMethodValueTest {
	static function main():Void {
		final root = "test/fixtures/native_array_method_value";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		Sys.println("ARRAY_METHOD_VALUE_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(path), path: path, root: root});
		final functions = [for (owner in typed.getTypedClasses()) for (fn in owner.getFunctions()) fn];
		final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), ".tmp/stage3-array-method-value", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "array method adaptation changed authored source";
		Sys.println("ARRAY_METHOD_VALUE_NATIVE:PASS");
		rejectNullReceiver();
	}

	/** Native nullable method storage remains unsupported; reject capture before an unsafe runtime call. */
	static function rejectNullReceiver():Void {
		final root = ".tmp/stage3-array-method-null";
		final source = "class Main { static function main():Void { var values:Array<Int> = null; "
			+ "try { final append = values.push; Sys.println(append == null ? 'null' : 'method'); } "
			+ "catch (error:Dynamic) { Sys.println(Std.string(error)); } } }";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		File.saveContent(path, source);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Main"], expected: "null\n"});
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram([typed], false), root + "/native", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: "Capturing a method from a null receiver is not supported\n"});
		Sys.println("ARRAY_METHOD_NULL_CAPTURE_REJECTION:PASS");
	}
}
