import sys.io.File;

/** A custom iterator must retain its authored comprehension until yield lowering. */
class M14KeyValueComprehensionTest {
	static function main():Void {
		final root = "test/fixtures/key_value_comprehension";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("KEY_VALUE_COMPREHENSION_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final fn = typed.getTypedClasses()[0].getFunctions()[0];
		final initializer = fn.getBody().getStatements()[1].getExpressions()[0];
		final loop = initializer.getExpressions()[0];
		if (initializer.getTag() != ArrayDecl || loop.getTag() != SourceFor || loop.getExpressions().length != 3)
			throw "custom comprehension lost its authored loop or selected protocol";
		switch TypedSourceSyntax.expression(loop) {
			case ESourceFor(KeyValue("key", "value"), EIdent("cursor"), EBinop("+", EIdent("key"), EIdent("value")), _):
			case _:
				throw "custom comprehension source reconstruction changed";
		}
		final protocol = loop.getExpressions()[2];
		final operands = protocol.getExpressions();
		final changed = protocol.withExpressions([operands[0], TypedExpr.boolLiteral(false, TyType.fromHintText("Bool"), null)].concat(operands.slice(2)));
		if (CompilerTypedTreeRevision.expression(fn.getStableIdentity(), protocol) == CompilerTypedTreeRevision.expression(fn.getStableIdentity(), changed))
			throw "iterator protocol operand changes must invalidate typed revisions";
		final revision = CompilerTypedTreeRevision.functionBody(fn);
		final lowered = TypedControlLowering.functionBody(fn);
		if (CompilerTypedTreeRevision.functionBody(fn) != revision)
			throw "iterator lowering mutated authored source";
		if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
			throw "iterator control lowering is not idempotent";
		final captures = TypedCapturePlan.afterLowering(fn, lowered);
		var iterations = 0;
		for (fact in captures.getBindings())
			if (fact.binding.getKind() == LoopVariable) {
				if (fact.creation != LoopIteration)
					throw "lowering changed per-iteration binding creation";
				iterations++;
			}
		if (iterations != 4)
			throw "key/value iteration declarations were lost";
		var iteration:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (expression.getTag() == VariableDeclaration && expression.getControlTarget() != null)
				iteration = expression;
			for (child in expression.getExpressions())
				visit(child);
		}
		function visitStatement(statement:TypedStmt):Void {
			for (expression in statement.getExpressions())
				visit(expression);
			for (child in statement.getStatements())
				visitStatement(child);
		}
		for (statement in lowered.getBody().getStatements())
			visitStatement(statement);
		if (iteration == null)
			throw "lowered comprehension must retain iteration creation targets";
		final escaped = lowered.withBody(new TypedFunctionBody([
			TypedStmt.expressionStmt(TypedExpr.variableDeclarations([iteration], TyType.fromHintText("Void"), null), null)
		], lowered.getBody().getSourceFingerprint()));
		var rejected = false;
		try {
			TypedCapturePlan.afterLowering(fn, escaped);
		} catch (error:haxe.Exception) {
			if (error.message != "iteration declaration is outside its exact lowered loop")
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "capture analysis admitted an iteration declaration outside its loop";
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("KEY_VALUE_COMPREHENSION_RUNTIME:PASS");
	}
}
