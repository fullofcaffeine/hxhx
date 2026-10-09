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
		for (kind in [
			TypedRuntimeTypeKind.IntCore,
			TypedRuntimeTypeKind.FloatCore,
			TypedRuntimeTypeKind.BoolCore
		]) {
			final target = new TypedRuntimeTypeTarget(kind);
			final type = target.getValueType();
			if (!type.isAbstractMeta()
				|| type.getNominalIdentity() != null
				|| target.getDeclarationIdentity() != null
				|| type.getCanonicalDisplay() != "Abstract<" + target.getInstanceType().getCanonicalDisplay() + ">")
				throw "primitive runtime type acquired a class identity";
			if (TyType.unify(type, TyType.nominal(new TyNominalTypeId("Class"), [target.getInstanceType()])) != null)
				throw "Abstract<T> was accepted as Class<T>";
			reject(() -> target.requireDeclarationIdentity());
			final literal = TypedExpr.runtimeTypeValue(target, null);
			@:privateAccess TypedBodyInvariant.assertExpr(literal, "owner");
			reject(() -> @:privateAccess TypedBodyInvariant.assertExpr(literal.withType(target.getInstanceType()), "owner"));
			final dependencies = new haxe.ds.StringMap<CompilerDependencyEdge>();
			@:privateAccess CompilerDependencyCollector.collectExpression(dependencies, "Main", null, null, literal);
			if (dependencies.iterator().hasNext())
				throw "primitive runtime type invented a provider dependency";
		}
		final parameter = new TyTypeParameterId("meta-test", 0, "T");
		final openMeta = TyType.abstractMeta(TyType.typeParameter(parameter));
		final bindings = TyTypeSubstitution.bind([parameter], [TyType.fromHintText("Int")], "meta-test");
		if (TyTypeSubstitution.parameterIdentities(openMeta).length != 1
			|| TyTypeSubstitution.apply(openMeta, bindings).getSemanticKey() != "abstract-meta<primitive:Int>"
			|| TyMethodGenericBinding.sameTypeConstructor(openMeta, TyType.nominal(new TyNominalTypeId("Class"), [TyType.typeParameter(parameter)])))
			throw "abstract meta-type lost its structural argument or constructor";
		final parent = new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("sample.Parent")));
		final other = new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("other.Parent")));
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
		final renamedTarget = new TypedRuntimeTypeTarget(parent.getKind(), "ParentAlias");
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
		// A String instance type is primitive, but its runtime class operand must
		// still observe the selected String provider's public interface.
		final coreTarget = new TypedRuntimeTypeTarget(StringCore);
		final coreTest = TypedExpr.runtimeTypeTest(value, coreTarget, null);
		final provider = new ResolvedModule("String", "String.hx", ParserStage.parse("extern class String {}", "String.hx"));
		final index = TyperIndex.build([provider]);
		final dependencies = new haxe.ds.StringMap<CompilerDependencyEdge>();
		@:privateAccess CompilerDependencyCollector.collectExpression(dependencies, "Main", index, null, coreTest);
		var observed = false;
		for (edge in dependencies)
			if (edge.providerModule == "String" && edge.factIdentity == "runtime-type-target:String")
				observed = true;
		if (!observed)
			throw "core String target lost its provider dependency";
		if (coreTarget.getSemanticKey() == new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("String"))).getSemanticKey())
			throw "core and nominal runtime representations acquired the same revision key";
		Sys.println("RUNTIME_TYPE_EXPRESSION_FACTS:PASS");
	}
}
