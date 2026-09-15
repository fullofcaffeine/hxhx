/** Checks immutable type-target facts before the executable projection is built. */
class M14RuntimeTypeExpressionFactsTest {
	static function reject(action:Void->Void):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "invalid runtime type expression was accepted";
	}

	static function main():Void {
		final parent = new TypedRuntimeTypeTarget(new TyNominalTypeId("sample.Parent"));
		final other = new TypedRuntimeTypeTarget(new TyNominalTypeId("other.Parent"));
		final value = TypedExpr.nullValue(TyType.fromHintText("Dynamic"), null);
		final test = TypedExpr.runtimeTypeTest(value, parent, null);
		final literal = TypedExpr.runtimeTypeValue(parent, null);
		if (!test.getTag().match(RuntimeTypeTest)
			|| test.getType().getSemanticKey() != "primitive:Bool"
			|| test.getExpressions().length != 1
			|| test.getExpressions()[0] != value)
			throw "runtime type test lost its Bool result or evaluated value child";
		if (!literal.getTag().match(RuntimeTypeValue)
			|| literal.getType().getSemanticKey() != "nominal:Class<nominal:sample.Parent>"
			|| literal.getExpressions().length != 0)
			throw "class value lost its meta-type or gained an evaluated source-name child";
		final copied = test.withExpressions([value]).withType(test.getType());
		if (copied.getRuntimeTypeTarget() != parent)
			throw "typed expression copy lost its exact runtime target";
		final revision = CompilerTypedTreeRevision.expression("owner", test);
		final renamedTarget = new TypedRuntimeTypeTarget(parent.getIdentity(), "ParentAlias");
		if (renamedTarget.getSemanticKey() != parent.getSemanticKey()
			|| CompilerTypedTreeRevision.expression("owner", TypedExpr.runtimeTypeTest(value, renamedTarget, null)) == revision)
			throw "source spelling must affect projection revision without changing target identity";
		if (CompilerTypedTreeRevision.expression("owner", copied) != revision
			|| CompilerTypedTreeRevision.expression("owner", TypedExpr.runtimeTypeTest(value, other, null)) == revision)
			throw "runtime type target was omitted from the semantic revision";
		@:privateAccess TypedBodyInvariant.assertExpr(test, "owner");
		@:privateAccess TypedBodyInvariant.assertExpr(literal, "owner");
		reject(() -> @:privateAccess TypedBodyInvariant.assertExpr(test.withType(TyType.fromHintText("String")), "owner"));
		reject(() -> @:privateAccess TypedBodyInvariant.assertExpr(test.withExpressions([]), "owner"));
		reject(() -> @:privateAccess TypedBodyInvariant.assertExpr(literal.withExpressions([value]), "owner"));
		Sys.println("RUNTIME_TYPE_EXPRESSION_FACTS:PASS");
	}
}
