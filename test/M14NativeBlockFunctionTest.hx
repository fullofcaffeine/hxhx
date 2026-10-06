/** Compare native block-function captures and control with independent upstream execution. */
class M14NativeBlockFunctionTest {
	static function main():Void {
		rejectedSource('class Main {static function main():Void {var callback = function(value:Dynamic):Int {return value;};}}',
			"OCaml block function requires per-return representation conversion");
		final root = "test/fixtures/native_block_function";
		final expected = "10\n99\n15\nbool\ntrue\nfalse\n1\ntext\neffect\nafter\n4\n2\n3\n36\n10\n11\n12\nselect\n21\nbad\n7\n3\nunmatched\nfalse\n12\n";
		if (run("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]) != expected)
			throw "upstream native block-function contract differs";
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		for (cls in typed.getBackendProjection().getClasses())
			for (fn in cls.getFunctions())
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						switch expression {
							case ELoweredControl(Throw, "", [value], _):
								fn.requireThrownValue(value);
								var rejected = false;
								try {
									fn.requireThrownValue(HxExpr.EString("bad"));
								} catch (message:String) {
									if (message != "thrown operand is absent from this exact function projection")
										throw message;
									rejected = true;
								}
								if (!rejected) throw "throw facts were borrowed from another expression";
							case _:
						}
						final facts = fn.findLambda(expression);
						if (facts == null)
							return;
						switch expression {
							case ELambda(_, ELoweredControl(FunctionBody, target, entries, position)):
								var rejected = false;
								try {
									backend.ocaml.Stage3OcamlFunctionBody.plan(facts, ELoweredControl(FunctionBody, target, entries.copy(), position));
								} catch (message:String) {
									if (message != "OCaml block function body is not its exact projected occurrence")
										throw message;
									rejected = true;
								}
								if (!rejected) throw "native block plan borrowed another body";
							case _:
						}
					}, _ -> {});
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		final output = ".tmp/native_block_function_" + Date.now().getTime();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), output, true);
		if (run(executable, []) != expected)
			throw "native block-function output differs; retained " + output;
		Sys.println("NATIVE_BLOCK_FUNCTION:PASS artifacts=" + output);
	}

	/** Unsupported valid source must fail at its named native boundary, never emit a placeholder. */
	static function rejectedSource(source:String, expected:String):Void {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		var rejected = false;
		for (cls in typed.getBackendProjection().getClasses())
			for (fn in cls.getFunctions())
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						final facts = fn.findLambda(expression);
						if (facts == null)
							return;
						switch expression {
							case ELambda(_, body):
								try {
									backend.ocaml.Stage3OcamlFunctionBody.plan(facts, body);
								} catch (message:String) {
									if (message != expected)
										throw message;
									rejected = true;
								}
							case _:
						}
					}, _ -> {});
		if (!rejected)
			throw "unsupported native block function was admitted: " + expected;
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "block-function command failed: " + stderr;
		return stdout;
	}
}
