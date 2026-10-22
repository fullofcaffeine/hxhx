/** Map literal types must retain the indexed provider and exact key/value types before target lowering. */
class M14SharedMapLiteralTypingTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/shared_map_literal_typing_seed/src",
			mainModule: "Main",
			requiredModules: ["haxe.ds.Map", "Array"]
		});
		final map = fixture.index.getByFullName("haxe.ds.Map");
		final array = fixture.index.getByFullName("Array");
		if (map == null || array == null)
			throw "Map typing requires real indexed Map and Array providers";
		final expected = [
			{name: "ints", key: "primitive:Int", value: "primitive:String"},
			{name: "strings", key: "primitive:String", value: "primitive:Int"},
			{name: "objects", key: "nominal:Main.Key", value: "primitive:String"},
			{name: "enums", key: "nominal:Main.Marker", value: "primitive:String"},
			{name: "written", key: "primitive:Int", value: "primitive:String"},
			{name: "generic", key: "primitive:String", value: ""}
		];
		final seen = new haxe.ds.StringMap<Bool>();
		for (cls in fixture.main.getTypedClasses())
			if (HxClassDecl.getName(cls.getSourceDeclaration()) == "Main")
				for (fn in cls.getFunctions()) {
					final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
					function inspect(expression:TypedExpr):Void {
						if (expression.getTag() == ArrayDecl) {
							final type = expression.getType();
							final arguments = type.getTypeArguments();
							if (name == "records" || name == "nested" || name == "genericArray") {
								if (type.getNominalIdentity() != array.getIdentity() || arguments.length != 1)
									throw "inferred array lost its indexed provider in " + name;
								var element = arguments[0];
								if (name == "nested" && element.getNominalIdentity() == array.getIdentity()) {
									if (element.getTypeArguments().length != 1)
										throw "nested array lost its element";
									element = element.getTypeArguments()[0];
								}
								if (name == "genericArray") {
									if (!element.isTypeParameter()
										|| element.getSemanticKey() != fn.getEnvironment().getParams()[0].getType().getSemanticKey())
										throw "inferred array lost its exact generic binder";
								} else if (!element.isAnonymous()
									|| element.getAnonymousFieldNames().join(",") != "name"
									|| element.getAnonymousFieldTypes()[0].getSemanticKey() != "primitive:String")
									throw "inferred array lost its structural element in " + name + ": " + element.getSemanticKey();
								seen.set(name, true);
							}
							if (name == "ordinary") {
								if (type.getNominalIdentity() != array.getIdentity()
									|| arguments.length != 1
									|| arguments[0].getSemanticKey() != "primitive:Int")
									throw "ordinary array lost its indexed Array<Int> type";
								seen.set(name, true);
							}
							for (entry in expected)
								if (entry.name == name) {
									if (type.getNominalIdentity() != map.getIdentity()
										|| arguments.length != 2
										|| arguments[0].getSemanticKey() != entry.key
										|| (name == "generic" ? !arguments[1].isTypeParameter()
											|| arguments[1].getSemanticKey() != fn.getEnvironment()
												.getParams()[0].getType().getSemanticKey() : arguments[1].getSemanticKey() != entry.value))
										throw "Map literal lost its exact type in " + name + ": " + type.getSemanticKey();
									seen.set(name, true);
								}
						}
						for (child in expression.getExpressions())
							inspect(child);
					}
					function statements(values:Array<TypedStmt>):Void {
						for (statement in values) {
							for (expression in statement.getExpressions())
								inspect(expression);
							statements(statement.getStatements());
						}
					}
					statements(fn.getBody().getStatements());
				}
		for (name in [
			"ints",
			"strings",
			"objects",
			"enums",
			"written",
			"generic",
			"ordinary",
			"records",
			"nested",
			"genericArray"
		])
			if (!seen.exists(name))
				throw "Map typing fixture did not observe " + name;
		Sys.println("SHARED_MAP_LITERAL_TYPING:PASS");
	}
}
