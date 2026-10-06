/** Constructor patterns must supply the same input type as an explicit enum annotation. */
class M14EnumParameterInferenceTest {
	static function main():Void {
		for (entry in [
			{name: "explicit", hint: ":Node", body: "return switch(node) { case Leaf(value): value; case Nest(child): read(child); };"},
			{name: "inferred", hint: "", body: "return switch(node) { case Leaf(value): value; case Nest(child): read(child); };"},
			{name: "statement", hint: "", body: "switch(node) { case Leaf(value): return value; case Nest(child): return read(child); }"},
			{name: "qualified", hint: "", body: "return switch(node) { case Node.Leaf(value): value; case Node.Nest(child): read(child); };"}
		]) {
			final root = ".tmp/enum_parameter_inference_" + entry.name;
			final source = "enum Node { Leaf(value:Int); Nest(child:Node); } class Main { static function read(node"
				+ entry.hint
				+ "):Int { "
				+ entry.body
				+ " } static function main():Void { if(read(Nest(Leaf(7))) != 7) throw 'wrong enum result'; } }";
			sys.FileSystem.createDirectory(root);
			sys.io.File.saveContent(root + "/Main.hx", source);
			final upstream = new sys.io.Process("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--interp"]);
			final stdout = upstream.stdout.readAll().toString();
			final stderr = upstream.stderr.readAll().toString();
			final code = upstream.exitCode();
			upstream.close();
			if (code != 0 || stdout != "")
				throw "upstream enum parameter failed: " + stdout + stderr;
			final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
			final index = TyperIndex.build([module]);
			final typed = TyperStage.typeResolvedModule(module, index);
			var found = false;
			for (cls in typed.getTypedClasses())
				for (fn in cls.getFunctions()) {
					if (HxFunctionDecl.getName(fn.getSourceDeclaration()) != "read")
						continue;
					found = true;
					if (fn.getEnvironment().getParams()[0].getType().getSemanticKey() != "nominal:Main.Node"
						|| index.getMethodBodyResults().signature(fn.getDeclaration()).getArgs()[0].getSemanticKey() != "nominal:Main.Node")
						throw "enum parameter was not published: " + entry.name;
					final sourceHint = HxFunctionArg.getTypeHint(HxFunctionDecl.getArgs(fn.getSourceDeclaration())[0]);
					if (entry.hint == "" && sourceHint != null && sourceHint != "")
						throw "enum inference changed the source annotation";
					final revision = CompilerTypedTreeRevision.functionBody(fn);
					typed.getBackendDeclaration();
					if (revision != CompilerTypedTreeRevision.functionBody(fn))
						throw "enum projection changed the typed body";
				}
			if (!found)
				throw "missing read declaration";
			JsRuntimeFixture.assertRuntime(typed, "Main", "");
			Sys.println("ENUM_PARAMETER_INFERENCE:PASS " + entry.name);
		}
	}
}
