/** Checks the actual shared typed tree before its backend projection is built. */
class M14RuntimeTypeNamespaceIntegrationTest {
	static function returned(classes:Array<TypedClass>, owner:String, name:String):TypedExpr {
		for (cls in classes)
			for (fn in cls.getFunctions())
				if (cls.getSemanticInfo().getFullName() == owner && HxFunctionDecl.getName(fn.getSourceDeclaration()) == name)
					for (statement in fn.getBody().getStatements())
						if (statement.getTag().match(Return))
							return statement.getExpressions()[0];
		throw "missing returned expression: " + owner + "." + name;
	}

	static function target(expression:TypedExpr, identity:String):Void {
		final selected = expression.getRuntimeTypeTarget();
		if (selected == null || selected.requireDeclarationIdentity().getCanonicalName() != identity)
			throw "runtime type expression lost selected identity: " + identity;
	}

	static function main():Void {
		final primitiveParsed = ParserStage.parse("class Main { static function intValue() return Int; static function floatValue() return Float; static function boolValue() return Bool; static function shadow(Int:Dynamic) return Int; }",
			"Main.hx");
		final primitiveIndex = TyperIndex.build([new ResolvedModule("Main", "Main.hx", primitiveParsed)]);
		final primitives = @:privateAccess TyperStage.buildTypedClasses(primitiveParsed, primitiveIndex, null, "Main");
		for (entry in [
			{method: "intValue", type: "Int"},
			{method: "floatValue", type: "Float"},
			{method: "boolValue", type: "Bool"}
		]) {
			final expression = returned(primitives.classes, "Main", entry.method);
			if (!expression.getTag().match(RuntimeTypeValue)
				|| expression.getType().getSemanticKey() != "abstract-meta<primitive:" + entry.type + ">")
				throw "primitive runtime value lost Abstract<T> identity: " + entry.type;
		}
		if (!returned(primitives.classes, "Main", "shadow").getTag().match(LocalRead))
			throw "a local must shadow a primitive runtime value";
		final root = "test/runtime_type_operands";
		final modules = [
			for (name in ["Main", "left.Parent", "right.Parent", "EnumValues"]) {
				final path = root + "/" + name.split(".").join("/") + ".hx";
				new ResolvedModule(name, path, ParserStage.parse(sys.io.File.getContent(path), path));
			}
		];
		final index = TyperIndex.build(modules);
		final loader = new ModuleLoader([root], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(modules);
		// Inspect the production typing boundary before TypedModule eagerly creates
		// backend declarations. The separate module test covers that next boundary.
		final built = @:privateAccess TyperStage.buildTypedClasses(ResolvedModule.getParsed(modules[0]), index, loader, "Main");
		TypedBodyInvariant.assertClasses(built.classes);
		for (name in ["classValue", "aliasValue", "qualifiedValue"]) {
			final value = returned(built.classes, "Main", name);
			final identity = name == "classValue" ? "left.Parent" : "right.Parent";
			if (!value.getTag().match(RuntimeTypeValue) || value.getType().getSemanticKey() != "nominal:Class<nominal:" + identity + ">")
				throw "class value lost its meta-type: " + name;
			target(value, identity);
		}
		final local = returned(built.classes, "Main", "localValue");
		if (!local.getTag().match(LocalRead) || local.getLocalBindings().length != 1)
			throw "same-spelled local class value lost its exact binding";
		final test = returned(built.classes, "Main", "typeOperand");
		if (!test.getTag().match(RuntimeTypeTest)
			|| test.getType().getSemanticKey() != "primitive:Bool"
			|| test.getExpressions().length != 1)
			throw "is must have a Bool result and only one evaluated child";
		target(test, "left.Parent");
		// A Bool result and a Dynamic operand do not otherwise mention Parent.
		// Its module must still be observed as a dependency of the type test.
		final dependencyOnly = TypedExpr.runtimeTypeTest(TypedExpr.nullValue(TyType.fromHintText("Dynamic"), null), test.getRuntimeTypeTarget(), null);
		final dependencies = new haxe.ds.StringMap<CompilerDependencyEdge>();
		@:privateAccess CompilerDependencyCollector.collectExpression(dependencies, "Main", index, index.getByFullName("Main"), dependencyOnly);
		var observesTarget = false;
		for (edge in dependencies)
			if (edge.consumerModule == "Main"
				&& edge.providerModule == "left.Parent"
				&& edge.kind == CompilerDependencyKind.PublicInterface)
				observesTarget = true;
		if (!observesTarget)
			throw "a runtime type target must retain its provider dependency";
		final call = returned(built.classes, "Main", "valueOperand");
		final arguments = call.getExpressions();
		if (!call.getTag().match(Call)
			|| arguments.length != 3
			|| !arguments[2].getTag().match(LocalRead)
			|| arguments[2].getRuntimeTypeTarget() != null)
			throw "Std.isOfType must evaluate its second argument through ordinary value lookup";
		final field = returned(built.classes, "Main.FieldValues", "read");
		if (!field.getTag().match(NameRead)
			|| field.getFieldInfo() == null
			|| field.getFieldInfo().getOwner().getCanonicalName() != "Main.FieldValues")
			throw "same-spelled field class value lost its exact field declaration";
		var foundInitializer = false;
		for (cls in built.classes)
			for (initializer in cls.getFieldInitializers())
				if (initializer.getField().getName() == "selected") {
					target(initializer.getExpression(), "left.Parent");
					foundInitializer = true;
				}
		if (!foundInitializer)
			throw "missing class-valued field initializer";
		if (returned(built.classes, "Main", "enumValue").getRuntimeTypeTarget() != null)
			throw "an enum constructor was reinterpreted as a class value";
		final enumBuilt = @:privateAccess TyperStage.buildTypedClasses(ResolvedModule.getParsed(modules[3]), index, loader, "EnumValues");
		final enumValue = returned(enumBuilt.classes, "EnumValues", "read");
		if (enumValue.getRuntimeTypeTarget() != null || !enumValue.getTag().match(EnumValue))
			throw "a same-spelled enum constructor must win over the imported class value";
		Sys.println("RUNTIME_TYPE_NAMESPACE:PASS");
	}
}
