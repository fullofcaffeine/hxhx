/** Candidate ranking and source constraints must agree on skipped method parameters. */
class M14MethodArgumentOrderTest {
	static function assertEqual(actual:String, expected:String):Void {
		if (actual != expected)
			throw 'argument order: expected $expected, got $actual';
	}

	static function main():Void {
		final signature = new TyFunSig("take", true, ["count", "label"], [TyType.fromHintText("Int"), TyType.fromHintText("String")], [true, false],
			[false, false], TyType.fromHintText("String"), HxPos.unknown());
		final sources:Array<HxExpr> = [EString("tail")];
		final types = [TyType.fromHintText("String")];
		final order = TyMethodArgumentOrder.select(signature, sources,
			(source, parameter, _) -> TyAssignmentCompatibility.classify(signature.getArgs()[parameter], types[source], Unchecked));
		if (order == null)
			throw "optional scalar could not be skipped";
		assertEqual(Std.string(order.parameterIndex(0)), "1");
		assertEqual(order.rankedTypes(types).map(type -> type.getCanonicalDisplay()).join(","), "Null,String");
		assertEqual(order.sourceContexts(signature.getArgs()).map(type -> type.getCanonicalDisplay()).join(","), "String");
		final copy = order.rankedTypes(types);
		copy[1] = TyType.fromHintText("Bool");
		assertEqual(order.rankedTypes(types)[1].getCanonicalDisplay(), "String");
		if (TyMethodArgumentOrder.select(signature, [], (_, _, _) -> Compatible) != null)
			throw "missing required suffix was accepted";
		if (TyMethodArgumentOrder.select(signature, [EInt(1), EString("tail"), EInt(2)], (_, _, _) -> Compatible) != null)
			throw "excess source operand was accepted";
		// This proves shared selection and inferred result type independently of the
		// native execution and publication checks in the neighboring tests.
		final source = 'class Main { static function take(count:Int=4, label:String):String return label; static function main():Void { var selected=take("tail"); if (selected!="tail") throw "selection changed"; } }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final generic = 'class Main { static function pick<T>(?unused:Int, value:T):T return value; static function main():Void { var chosen=pick("tail"); } }';
		final genericModule = new ResolvedModule("Main", "Main.hx", ParserStage.parse(generic, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(genericModule, TyperIndex.build([genericModule]));
		var selected = 0;
		function inspectExpression(value:TypedExpr):Void {
			final declaration = value.getDeclaration();
			if (value.getTag() == Call && declaration != null && declaration.getSignature().getName() == "pick") {
				assertEqual(value.getType().getCanonicalDisplay(), "String");
				assertEqual(Std.string(value.getExpressions().length), "2");
				assertEqual(value.getExpressions()[1].getType().getCanonicalDisplay(), "String");
				selected++;
			}
			for (child in value.getExpressions())
				inspectExpression(child);
		}
		function inspectStatement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				inspectExpression(child);
			for (child in value.getStatements())
				inspectStatement(child);
		}
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				for (statement in fn.getBody().getStatements())
					inspectStatement(statement);
		if (selected != 1)
			throw "generic omission lost its exact typed call";
		Sys.println("METHOD_ARGUMENT_ORDER:PASS");
	}
}
