/** Expected collection types must reach literal nodes, not only their enclosing declarations. */
class M14ContextualMapLiteralTypingTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/shared_map_literal_typing_seed/contextual",
			mainModule: "Main",
			requiredModules: ["haxe.ds.Map", "Array"]
		});
		final map = fixture.index.getByFullName("haxe.ds.Map");
		final array = fixture.index.getByFullName("Array");
		final mapType = TyType.nominal(map.getIdentity(), [TyType.fromHintText("Int"), TyType.fromHintText("String")]);
		final arrayType = TyType.nominal(array.getIdentity(), [TyType.fromHintText("Int")]);
		final stringMapType = TyType.nominal(map.getIdentity(), [TyType.fromHintText("String"), TyType.fromHintText("String")]);
		final failures = new Array<String>();
		final observed = new haxe.ds.StringMap<Int>();
		function inspect(expression:TypedExpr, expected:TyType, label:String):Void {
			if (expression.getTag() == ArrayDecl) {
				observed.set(label, (observed.exists(label) ? observed.get(label) : 0) + 1);
				if (expression.getType().getSemanticKey() != expected.getSemanticKey()) {
					final message = label + ": " + expression.getType().getSemanticKey() + " instead of " + expected.getSemanticKey();
					failures.push(message);
					Sys.println("CONTEXTUAL_MAP_LITERAL_TYPING:FAIL " + message);
				}
			}
			for (child in expression.getExpressions())
				inspect(child, expected, label);
		}
		function statements(values:Array<TypedStmt>, expected:TyType, label:String):Void {
			for (statement in values) {
				for (expression in statement.getExpressions())
					inspect(expression, expected, label);
				statements(statement.getStatements(), expected, label);
			}
		}
		for (cls in fixture.main.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Main") {
				for (initializer in cls.getFieldInitializers())
					if (initializer.getField().getName() == "field")
						inspect(initializer.getExpression(), mapType, "field");
				for (fn in cls.getFunctions()) {
					final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
					if ([
						"returned",
						"local",
						"argument",
						"generic",
						"ordinary",
						"overloadArray",
						"overloadMap",
						"genericArgument",
						"extensionArgument",
						"genericExtensionArgument",
						"conditionalMap",
						"conditionalArray",
						"assignedLocal",
						"assignedField",
						"assignedElement",
						"assignedArray",
						"genericAssignment"
					].indexOf(name) < 0)
						continue;
					final expected = switch (name) {
						case "genericExtensionArgument":
							final witnessType = fn.getEnvironment().getParams()[0].getType();
							if (!witnessType.isTypeParameter())
								throw "extension fixture lost its caller-owned generic parameter";
							TyType.nominal(map.getIdentity(), [TyType.fromHintText("String"), witnessType]);
						case "generic" | "genericAssignment": fn.getEnvironment().getReturnType();
						case "ordinary" | "overloadArray" | "conditionalArray" | "assignedArray": arrayType;
						case "genericArgument": stringMapType;
						case _: mapType;
					};
					statements(fn.getBody().getStatements(), expected, name);
				}
			}
		for (name in [
			"field",
			"returned",
			"local",
			"argument",
			"generic",
			"ordinary",
			"overloadArray",
			"overloadMap",
			"genericArgument",
			"extensionArgument",
			"genericExtensionArgument",
			"conditionalMap",
			"conditionalArray",
			"assignedLocal",
			"assignedField",
			"assignedElement",
			"assignedArray",
			"genericAssignment"
		])
			if (!observed.exists(name) || observed.get(name) != (name == "conditionalMap" || name == "conditionalArray" ? 2 : 1))
				throw "contextual literal fixture did not observe every literal in " + name;
		if (failures.length > 0)
			throw failures.join("\n");
		Sys.println("CONTEXTUAL_MAP_LITERAL_TYPING:PASS");
		M14ContextualMapEntriesTest.run();
	}
}
