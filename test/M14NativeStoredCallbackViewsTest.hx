/** Run the complete native callback fixture directly while the enclosing suite also checks the standalone target. */
class M14NativeStoredCallbackViewsTest {
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "Native stored callback observation failed: " + command + "\n" + output + errors;
	}

	static function main():Void {
		final fixture = "test/fixtures/stage3_stored_callback_views";
		final path = fixture + "/Main.hx";
		final source = sys.io.File.getContent(path);
		final expected = sys.io.File.getContent(fixture + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", fixture, "--run", "Main"], expected);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/native_stored_callback_views", true);
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable], expected);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "Native callback emission changed typed source";
		Sys.println("NATIVE_STORED_CALLBACK_VIEWS:PASS");
	}
}
