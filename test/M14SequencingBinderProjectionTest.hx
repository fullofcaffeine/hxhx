/** Discarded expressions must not declare a local or shadow an authored binding. */
class M14SequencingBinderProjectionTest {
	static function assertSelectedBinding(expression:TypedExpr, authored:TyLocalBinding):Int {
		var reads = 0;
		if (expression.getTag() == LocalRead && expression.getTexts()[0] == authored.getSourceName()) {
			final bindings = expression.getLocalBindings();
			if (bindings.length != 1 || bindings[0].getIdentity() != authored.getIdentity())
				throw "discarded expression shadows the authored result binding";
			reads++;
		}
		for (child in expression.getExpressions())
			reads += assertSelectedBinding(child, authored);
		return reads;
	}

	static function assertNoDiscardedDeclaration(expression:TypedExpr):Void {
		if ((expression.getTag() == Lambda || expression.getTag() == SourceFunction) && expression.getLocalBindings().length != 0)
			throw "expression statement introduced a lambda declaration";
		for (child in expression.getExpressions())
			assertNoDiscardedDeclaration(child);
	}

	static function module():TypedModule {
		final source = 'class Main {
 static var counter:Int = 0;
 static var initialized:Int = { counter = counter + 1; counter + 10; };
 static function value():Int {
  var __hxhx_lambda_seq_0 = 4;
  var result = { counter = counter + 1; counter = counter + 1; __hxhx_lambda_seq_0; };
  return result;
 }
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	/** An unused parameter and a captured parameter both remain real declarations. */
	static function assertAuthoredLookalikes():Void {
		final source = 'class Lookalikes {
 static function check():Void {
  var unused = function(__hxhx_lambda_seq_0:Int):Int { return 7; };
  var captured = function(__hxhx_lambda_seq_0:Int) {
   return function():Int { return __hxhx_lambda_seq_0; };
  };
 }
}';
		final resolved = new ResolvedModule("Lookalikes", "Lookalikes.hx", ParserStage.parse(source, "Lookalikes.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final lambdas = new Array<TypedExpr>();
		function visit(expression:TypedExpr):Void {
			if ((expression.getTag() == Lambda || expression.getTag() == SourceFunction)
				&& expression.getLocalBindings().length == 1
				&& expression.getLocalBindings()[0].getSourceName() == "__hxhx_lambda_seq_0")
				lambdas.push(expression);
			for (child in expression.getExpressions())
				visit(child);
		}
		for (statement in typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements())
			for (expression in statement.getExpressions())
				visit(expression);
		if (lambdas.length != 2)
			throw "authored prefix parameters were removed or given synthetic declarations";
		final unused = lambdas[0].getLocalBindings()[0];
		final captured = lambdas[1].getLocalBindings()[0];
		if (unused.getKind() != LambdaParameter || captured.getKind() != LambdaParameter || unused.getIdentity() == captured.getIdentity())
			throw "authored lambda parameters lost their distinct declaration identities";
		if (assertSelectedBinding(lambdas[0], unused) != 0 || assertSelectedBinding(lambdas[1], captured) != 1)
			throw "unusedness or capture changed the selected authored parameter";
		final catalog = typed.getBackendProjection().getClasses()[0].getFunctions()[0].getLocalCatalog();
		for (binding in [unused, captured]) {
			final projected = catalog.findByIdentity(binding.getIdentity().getCanonicalKey());
			if (projected == null || projected.getBinding().getIdentity() != binding.getIdentity())
				throw "strict projection replaced an authored parameter identity";
		}
	}

	static function main():Void {
		final typed = module();
		final statements = typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements();
		final authored = statements[0].getLocalBindings()[0];
		final result = statements[1].getExpressions()[0];
		if (authored == null || authored.getSourceName() != "__hxhx_lambda_seq_0")
			throw "missing authored declaration in semantic fixture";
		if (assertSelectedBinding(result, authored) != 1)
			throw "expected exactly one read of the authored result binding";
		assertNoDiscardedDeclaration(result);
		for (initializer in typed.getTypedClasses()[0].getFieldInitializers())
			assertNoDiscardedDeclaration(initializer.getExpression());
		assertAuthoredLookalikes();
		Sys.println("PARSED_SEQUENCING_BINDING:PASS");
		final type = TyType.fromHintText("Int");
		final expression = TypedBodySource.expression(TypedExpr.block([
			TypedExpr.intLiteral(1, type, null),
			TypedExpr.intLiteral(2, type, null),
			TypedExpr.intLiteral(3, type, null)
		], type, null));
		switch (expression) {
			case EDiscardThen(EInt(1), EDiscardThen(EInt(2), EInt(3))):
			case _:
				throw "typed block projection lost ordered effects or final result";
		}
		Sys.println("TYPED_BLOCK_SEQUENCING_PROJECTION:PASS");
		final original:HxExpr = EDiscardThen(EInt(1), EInt(2));
		final changedEffect:HxExpr = EDiscardThen(EInt(3), EInt(2));
		final changedResult:HxExpr = EDiscardThen(EInt(1), EInt(4));
		final originalFingerprint = TypedBodyFingerprint.forExpression(original);
		final originalTyped = TypedBodyBuilder.buildExpression(original, HxPos.unknown(), null);
		final originalRevision = CompilerTypedTreeRevision.expression("sequence", originalTyped);
		for (changed in [changedEffect, changedResult]) {
			if (TypedBodyFingerprint.forExpression(changed) == originalFingerprint)
				throw "source fingerprint ignored a sequencing child";
			final changedTyped = TypedBodyBuilder.buildExpression(changed, HxPos.unknown(), null);
			if (CompilerTypedTreeRevision.expression("sequence", changedTyped) == originalRevision)
				throw "semantic revision ignored a sequencing child";
		}
		final visited = new Array<HxExpr>();
		TypedBackendSourceWalk.expression(original, node -> visited.push(node));
		if (visited.length != 3 || !visited[1].match(EInt(1)) || !visited[2].match(EInt(2)))
			throw "source walk lost effect-before-result order";
		final cls = typed.getBackendProjection().getClasses()[0];
		final fn = cls.getFunctions()[0];
		final authoredProjection = fn.getLocalCatalog().findByProjectedName("__hxhx_lambda_seq_0");
		if (authoredProjection == null)
			throw "authored prefix collision disappeared";
		for (statement in fn.getBody())
			TypedBackendSourceWalk.statement(statement, node -> {
				if (node.match(ELambda(_, _)))
					throw "strict projection recreated a discarded lambda";
			}, _ -> {});
		Sys.println("SEQUENCING_BINDER_PROJECTION:PASS");
	}
}
