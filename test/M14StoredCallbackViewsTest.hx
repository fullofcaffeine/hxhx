/** A callback type conversion preserves invocation, aliases, and the original function identity. */
class M14StoredCallbackViewsTest {
	static function main():Void {
		verifySharedFixture("test/fixtures/ocaml_closed_callback_views", ".tmp/closed_callback_views");
		final root = ".tmp/stored_callback_views";
		final fixture = verifySharedFixture("test/fixtures/stage3_stored_callback_views", root);
		final module = new ResolvedModule("Main", fixture.path, ParserStage.parse(fixture.source, fixture.path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable], fixture.expected);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "stored callback emission changed typed source";
		Sys.println("STORED_CALLBACK_VIEWS_NATIVE:PASS");
	}

	/** Each complete source program must compile and execute before its output is accepted. */
	static function verifySharedFixture(fixture:String, root:String):{source:String, path:String, expected:String} {
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final source = sys.io.File.getContent(fixture + "/Main.hx");
		final expected = sys.io.File.getContent(fixture + "/expected.stdout");
		sys.io.File.saveContent(path, source);
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("STORED_CALLBACK_VIEWS_UPSTREAM:PASS " + fixture);
		// Capture-free factory identity differs between upstream eval and Neko.
		// Record that distinction without changing the native eval-parity contract.
		if (sys.FileSystem.exists(fixture + "/expected.neko.stdout")) {
			final nekoOutput = root + "/upstream.n";
			requireSuccess("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--neko", nekoOutput]);
			observe("neko", [nekoOutput], sys.io.File.getContent(fixture + "/expected.neko.stdout"));
			Sys.println("STORED_CALLBACK_VIEWS_NEKO_OBSERVATION:PASS " + fixture);
		}
		// The standalone target owns callback representation. Keep its full
		// source path in this regression so a diagnostic-emitter fix cannot
		// accidentally stand in for the shared target's behavior.
		final standalone = root + "/standalone";
		requireSuccess("node_modules/.bin/haxe", [
			"-cp",
			root,
			"-main",
			"Main",
			"--no-output",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"ocaml_no_build",
			"-D",
			"ocaml_lowering_report",
			"-D",
			"ocaml_output=" + standalone
		]);
		// An automatic build can report a Dune error as a compiler warning.
		// Require the native build's own exit status before observing output.
		requireSuccess("dune", ["build", "--root", standalone, "./standalone.exe"]);
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", standalone + "/_build/default/standalone.exe"], expected);
		Sys.println("STORED_CALLBACK_VIEWS_SHARED_NATIVE:PASS " + fixture);
		if (sys.FileSystem.exists(fixture + "/verify-report.js"))
			requireSuccess("node", [fixture + "/verify-report.js", standalone]);
		return {source: source, path: path, expected: expected};
	}

	/** Require source generation and native checking to succeed before running an artifact. */
	static function requireSuccess(command:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "stored callback build failed: " + command + " (exit " + code + ")\n" + output + errors;
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
