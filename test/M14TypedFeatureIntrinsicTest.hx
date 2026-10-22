import sys.io.File;

/** Exact typed feature nodes retain source branches without choosing reachability or stealing ordinary calls. */
class M14TypedFeatureIntrinsicTest {
	static function typeModule(module:String):TypedModule {
		final path = "test/fixtures/js_feature_intrinsic/" + module + ".hx";
		final resolved = new ResolvedModule(module, path, ParserStage.parse(File.getContent(path), path));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	/** Visit nested statements and expressions so a feature cannot disappear inside a source group. */
	static function visit(module:TypedModule, inspect:TypedExpr->Void):Void {
		function expression(node:TypedExpr):Void {
			inspect(node);
			for (child in node.getExpressions())
				expression(child);
		}
		function statement(node:TypedStmt):Void {
			for (child in node.getExpressions())
				expression(child);
			for (child in node.getStatements())
				statement(child);
		}
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
	}

	static function main():Void {
		final module = typeModule("Main");
		var definitions = 0;
		var selections = 0;
		var selected:Null<TypedExpr> = null;
		visit(module, function(node) {
			switch node.getTag() {
				case FeatureDefinition:
					definitions++;
					if (node.getTexts()[0] != "probe.enabled"
						|| node.getExpressions().length != 1
						|| node.getType().getSemanticKey() != node.getExpressions()[0].getType().getSemanticKey())
						throw "feature definition lost its name or operand type";
				case FeatureSelection:
					selections++;
					if (node.getExpressions().length != 2 || node.getDeclaration() != null)
						throw "feature selection lost a branch or gained a callable declaration";
					if (node.getTexts()[0] == "probe.enabled")
						selected = node;
				case _:
			}
		});
		if (definitions != 1 || selections != 2 || selected == null)
			throw "typed feature occurrences differ from authored source";
		if (selected.getExpressions()[0].getTag() != SourceGroup)
			throw "feature selection flattened its source block before program selection";
		final syntax = TypedSourceSyntax.expression(selected);
		if (!syntax.match(ECall(EIdent("__feature__"), _)))
			throw "typed feature lost its authored syntax";
		final originalRevision = CompilerTypedTreeRevision.expression("feature-test", selected);
		final renamed = TypedExpr.featureSelection("other", selected.getExpressions()[0], selected.getExpressions()[1], selected.getPosition());
		final changedBranch = selected.withExpressions([selected.getExpressions()[1], selected.getExpressions()[0]]);
		if (originalRevision == CompilerTypedTreeRevision.expression("feature-test", renamed)
			|| originalRevision == CompilerTypedTreeRevision.expression("feature-test", changedBranch))
			throw "typed feature revision ignored its name or branch order";
		var rejection = "";
		try {
			module.getBackendProjection();
		} catch (error:haxe.Exception) {
			rejection = error.message;
		}
		if (rejection.indexOf("feature intrinsics require program-owned selection") < 0
			|| originalRevision != CompilerTypedTreeRevision.expression("feature-test", selected))
			throw "projection did not reject unresolved features without changing source facts";

		var ordinary = 0;
		visit(typeModule("FeatureShadowing"), function(node) {
			if (node.getTag() == FeatureDefinition || node.getTag() == FeatureSelection)
				throw "intrinsic recognition captured a resolved local or method";
			if (node.getTag() == Call) {
				final callee = node.getExpressions()[0];
				if (callee.getTexts().length == 1
					&& (callee.getTexts()[0] == "__feature__" || callee.getTexts()[0] == "__define_feature__"))
					ordinary++;
			}
		});
		if (ordinary != 2)
			throw "shadowing contract lost an ordinary call";
		final raw = TypedExpr.call(TypedExpr.nameRead("__feature__", TyType.unknown(), null), [
			TypedExpr.stringLiteral("quoted", TyType.fromHintText("String"), null),
			TypedExpr.intLiteral(1, TyType.fromHintText("Int"), null)
		], null, TyType.unknown(), null);
		if (TypedFeatureIntrinsic.capture(raw).getTag() != FeatureSelection)
			throw "quote control does not contain a recognizable intrinsic";
		final quoted = TypedExpr.macroExpr(raw, [], TyType.fromHintText("Dynamic"), null);
		if (TypedFeatureIntrinsic.capture(quoted) != quoted)
			throw "intrinsic recognition traversed a quoted macro";
		final functionOwner = module.getTypedClasses()[0].getFunctions()[0];
		for (malformed in [selected.withExpressions([]), selected.withType(TyType.fromHintText("String"))]) {
			var invalid = "";
			try {
				TypedBodyInvariant.assertFunction(functionOwner.withBody(new TypedFunctionBody([TypedStmt.expressionStmt(malformed, null)],
					functionOwner.getBody().getSourceFingerprint())));
			} catch (error:haxe.Exception) {
				invalid = error.message;
			}
			if (invalid.indexOf("feature") < 0)
				throw "typed feature invariant accepted a malformed node";
		}
		Sys.println("TYPED_FEATURE_INTRINSIC:PASS");
	}
}
