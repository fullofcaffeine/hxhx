import sys.io.File;

/** Compare exact parameter bindings and generated execution with upstream Haxe. */
class M14SourceParameterInferenceTest {
	static function main():Void {
		final root = "test/fixtures/source_parameter_inference";
		final expected = "15\n15\n15\n15\n";
		final upstream = run("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]);
		if (upstream != expected)
			throw "upstream parameter contract differs: " + upstream;
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final parameters = new Array<String>();
		final identities = new haxe.ds.StringMap<String>();
		function expression(node:TypedExpr):Void {
			for (binding in node.getLocalBindings())
				if (binding.getKind() == LambdaParameter) {
					final identity = binding.getIdentity().getCanonicalKey();
					final type = binding.getType().getSemanticKey();
					if (!identities.exists(identity)) {
						identities.set(identity, type);
						parameters.push(type);
					} else if (identities.get(identity) != type) {
						throw "parameter read disagrees with its declared type";
					}
				}
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (value in node.getExpressions())
				expression(value);
			for (child in node.getStatements())
				statement(child);
		}
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (entry in fn.getBody().getStatements())
					statement(entry);
		if (parameters.join(",") != "primitive:Int,primitive:Int,primitive:Int,dynamic,primitive:Int")
			throw "parameter bindings lost inferred or explicit types: " + parameters.join(",");
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("SOURCE_PARAMETER_INFERENCE_JS:PASS");
		final output = ".tmp/source_parameter_inference_" + Date.now().getTime();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), output, true);
		if (run(executable, []) != expected)
			throw "native parameter runtime differs; retained " + output;
		Sys.println("SOURCE_PARAMETER_INFERENCE_NATIVE:PASS");
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "parameter fixture command failed: " + errors;
		return output;
	}
}
