import sys.io.File;

/** Method values must carry provider identity through dependencies, revisions, projection and runtime. */
class M14StaticMethodValueIdentityTest {
	static function main():Void {
		final resolved = [
			for (name in ["Main", "Provider", "Alternate"]) {
				final path = "test/fixtures/static_method_values/" + name + ".hx";
				new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path));
			}
		];
		final index = TyperIndex.build(resolved);
		final typed = [for (module in resolved) TyperStage.typeResolvedModule(module, index)];
		final dependencies = CompilerDependencyCollector.collect(typed, index);
		for (name in ["Provider", "Alternate"]) {
			final owner = index.getByFullName(name);
			final selected = owner.declarationForSignature(owner.staticMethod("choose"));
			var found = false;
			for (edge in dependencies.getEdges())
				if (edge.consumerModule == "Main"
					&& edge.providerModule == name
					&& edge.factIdentity == "declaration:" + selected.getIdentity().getCanonicalKey())
					found = true;
			if (!found)
				throw "method value lost its provider dependency: " + name;
		}
		function revision(provider:String):String {
			final source = "import " + provider + ".choose as selected; class Consumer { static function run():Void { final value = selected; } }";
			final consumer = new ResolvedModule("Consumer", "Consumer.hx", ParserStage.parse(source, "Consumer.hx"));
			final localIndex = TyperIndex.build([resolved[1], resolved[2], consumer]);
			final module = TyperStage.typeResolvedModule(consumer, localIndex);
			return CompilerTypedTreeRevision.functionBody(module.getTypedClasses()[0].getFunctions()[0]);
		}
		if (revision("Provider") == revision("Alternate"))
			throw "method value provider change did not change the body revision";
		final output = ".tmp/static_method_values_" + Date.now().getTime();
		sys.FileSystem.createDirectory(output);
		final script = output + "/main.js";
		new backend.js.JsBackend().emit(new MacroExpandedProgram(typed, false),
			new backend.BackendContext(output, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node", script]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0 || stdout != "3\n4\n105\n107\n")
			throw "static method values differ; retained " + script + ": " + stdout + stderr;
		sys.FileSystem.deleteFile(script);
		if (sys.FileSystem.exists(script + ".map"))
			sys.FileSystem.deleteFile(script + ".map");
		sys.FileSystem.deleteDirectory(output);
		Sys.println("STATIC_METHOD_VALUE_IDENTITY:PASS");
	}
}
