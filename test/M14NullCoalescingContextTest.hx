/** Compare fallback context and lazy evaluation with upstream using real collection providers. */
class M14NullCoalescingContextTest {
	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/null_coalescing_context/Main.hx");
		final output = JsRuntimeFixture.reserveOutput();
		sys.io.File.saveContent(output + "/Main.hx", source);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", output, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [output + "/upstream.js"]);
		Sys.println("NULL_COALESCING_CONTEXT_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [{path: "Main.hx", source: source}],
			requiredModules: ["Array", "haxe.ds.Map"]
		});
		final modules = program.getTypedModules();
		final revisions = modules.map(module -> CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity());
		JsRuntimeFixture.assertProgramRuntime(program, "Main", "");
		for (index in 0...modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(modules[index]).getCanonicalIdentity() != revisions[index])
				throw "fallback emission changed retained typing";
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		assertInvalidFallbacks();
		Sys.println("NULL_COALESCING_CONTEXT:PASS");
	}

	/** Strict checking must reject incompatible scalar, collection, and callback fallbacks. */
	static function assertInvalidFallbacks():Void {
		for (entry in [
			{name: "scalar", body: 'var left:Null<Int>=null;var result=left??"text";'},
			{name: "array", body: 'var left:Null<Array<Int>>=null;var result=left??["text"];'},
			{name: "callback", body: 'var left:Null<(Int)->Int>=null;var result=left??(value->"text");'}
		]) {
			final output = JsRuntimeFixture.reserveOutput();
			final path = output + "/Main.hx";
			final source = "class Main {static function main():Void {" + entry.body + "}}";
			sys.io.File.saveContent(path, source);
			final upstream = new sys.io.Process("haxe", ["-cp", output, "-main", "Main", "--no-output", "-js", output + "/unused.js"]);
			upstream.stdout.readAll();
			final errors = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (code == 0 || errors.indexOf("should be") < 0)
				throw "upstream fallback rejection changed: " + entry.name + errors;
			final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
			final args = hxhx.Stage1Compiler.Stage1Args.parse(["-main", "Main"], true);
			final index = TyperIndex.buildHeaders([resolved]);
			final loader = new ModuleLoader([hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(args)], new haxe.ds.StringMap<String>(), index, null, false);
			loader.markResolvedAlready([resolved]);
			final previous = Sys.getEnv("HXHX_TYPER_STRICT");
			Sys.putEnv("HXHX_TYPER_STRICT", "1");
			var diagnostic = "";
			try {
				TyperStage.typeResolvedModule(resolved, index, loader);
			} catch (error:haxe.Exception) {
				diagnostic = error.message;
			}
			Sys.putEnv("HXHX_TYPER_STRICT", previous == null ? "" : previous);
			if (diagnostic.indexOf("not compatible") < 0)
				throw "candidate fallback rejection changed: " + entry.name + diagnostic;
			@:privateAccess JsRuntimeFixture.removeOutput(output);
			Sys.println("NULL_COALESCING_REJECTION:PASS " + entry.name);
		}
	}
}
