/** Compare each native block return with independent upstream values and side effects. */
class M14BlockReturnConversionTest {
	static function main():Void {
		final cases = [
			{
				name: "dynamic_to_int",
				source: "var value:Dynamic=7; var callback=function(value:Dynamic):Int { return value; }; Sys.println(callback(value));",
				expected: "7\n"
			},
			{
				name: "mixed_dynamic",
				source: "var callback=function(first:Bool):Dynamic { if(first) return true; var value:Dynamic=9; return value; }; Sys.println(callback(true)); Sys.println(callback(false));",
				expected: "true\n9\n"
			},
			{
				name: "nested_control",
				source: "var callback=function(first:Bool):Dynamic { var inner=function(value:Dynamic):String { return value; }; var text:Dynamic='inner'; Sys.println(inner(text)); for(i in 0...2) { if(first) return false; } try { throw 'caught'; } catch(error:Dynamic) { Sys.println(error); return 'outer'; } }; Sys.println(callback(true)); Sys.println(callback(false));",
				expected: "inner\nfalse\ninner\ncaught\nouter\n"
			},
			{
				name: "return_effect",
				source: "var callback=function(value:Dynamic):Bool { Sys.println('effect'); return value; }; var value:Dynamic=true; Sys.println(callback(value));",
				expected: "effect\ntrue\n"
			}
		];
		// Separate lexical scopes keep each control independent in one native build.
		final root = ".tmp/block_return_conversion";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final body = cases.map(entry -> "Sys.println('" + entry.name + "'); { " + entry.source + " }").join(" ");
		final source = "class Main { static function main():Void { " + body + " } }";
		final expected = cases.map(entry -> entry.name + "\n" + entry.expected).join("");
		sys.io.File.saveContent(path, source);
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], expected);
		Sys.println("BLOCK_RETURN_UPSTREAM:PASS cases=" + cases.length);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		auditReturns(typed);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
		observe(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable], expected);
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "block return conversion changed typed source";
		Sys.println("BLOCK_RETURN_NATIVE:PASS cases=" + cases.length);
	}

	/** Reject copied operations, foreign owners, and mutation of a checked return operand. */
	static function auditReturns(typed:TypedModule):Void {
		var checked = 0;
		for (cls in typed.getBackendProjection().getClasses())
			for (fn in cls.getFunctions())
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, expression -> {
						final facts = fn.findLambda(expression);
						if (facts == null)
							return;
						switch expression {
							case ELambda(_, body) if (body.match(ELoweredControl(FunctionBody, _, _, _))):
								final plan = backend.ocaml.Stage3OcamlFunctionBody.plan(facts, body);
								for (entry in plan.returns) {
									checked++;
									reject(() -> entry.fact.assertCurrent("foreign", "foreign"), "return occurrence belongs to another executable or revision");
									switch entry.fact.expression {
										case ELoweredControl(Return, target, values, position):
											reject(() -> {
												facts.requireReturn(ELoweredControl(Return, target, values.copy(), position));
											}, "return is absent from this exact lambda projection");
											if (values.length > 0) {
												final original = values[0];
												values[0] = HxExpr.EString("mutated return");
												reject(() -> {
													facts.requireReturn(entry.fact.expression);
												}, "lambda occurrence changed after projection");
												values[0] = original;
												facts.requireReturn(entry.fact.expression);
											}
										case _: throw "return contract lost its operation";
									}
								}
							case _:
						}
					}, _ -> {});
		if (checked == 0)
			throw "block return test did not inspect a return";
	}

	static function reject(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (message:String) {
			if (message != expected)
				throw message;
			return;
		}
		throw "invalid block return fact was accepted: " + expected;
	}

	/** Runtime output must match an authored expectation, including evaluation order. */
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "block return contract differs; expected " + expected + " but received " + output + errors;
	}
}
