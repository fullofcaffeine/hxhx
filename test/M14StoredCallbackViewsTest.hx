/** A callback type conversion preserves invocation, aliases, and the original function identity. */
class M14StoredCallbackViewsTest {
	static function main():Void {
		final root = ".tmp/stored_callback_views";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = sys.io.File.getContent("test/fixtures/stage3_stored_callback_views/Main.hx");
		final expected = sys.io.File.getContent("test/fixtures/stage3_stored_callback_views/expected.stdout");
		sys.io.File.saveContent(path, source);
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("STORED_CALLBACK_VIEWS_UPSTREAM:PASS");
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable], expected);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "stored callback emission changed typed source";
		Sys.println("STORED_CALLBACK_VIEWS_NATIVE:PASS");
	}

	/** Observe actual native execution against values specified independently of generated code. */
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "stored callback views differ: " + output + errors;
	}
}
