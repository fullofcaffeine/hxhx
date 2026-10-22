import sys.io.File;

/** Prove precise loop-local types before observing custom iterator execution. */
class M14KeyValueProtocolTest {
	static function main():Void {
		final root = "test/fixtures/key_value_protocol";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("KEY_VALUE_PROTOCOL_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([module]);
		final typed = TyperStage.typeResolvedModule(module, index);
		var bindingsSeen = 0;
		final identities = new haxe.ds.StringMap<Bool>();
		function inspectBindings(bindings:Array<TyLocalBinding>):Void {
			for (binding in bindings)
				if (binding.getKind().match(LoopVariable)) {
					final identity = binding.getIdentity().getCanonicalKey();
					if (!identities.exists(identity)) {
						identities.set(identity, true);
						bindingsSeen++;
					}
					if (binding.getType().getSemanticKey() != "primitive:Int")
						throw "iterator local must retain Int, got " + binding.getType().getSemanticKey();
				}
		}
		function inspectExpression(expression:TypedExpr):Void {
			inspectBindings(expression.getLocalBindings());
			for (child in expression.getExpressions())
				inspectExpression(child);
		}
		function inspect(statement:TypedStmt):Void {
			inspectBindings(statement.getLocalBindings());
			for (expression in statement.getExpressions())
				inspectExpression(expression);
			for (child in statement.getStatements())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody().getStatements())
					inspect(statement);
		if (bindingsSeen != 20)
			throw "custom iterator coverage changed";
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("KEY_VALUE_PROTOCOL_RUNTIME:PASS");
	}
}
