/** Checks that runtime type operands retain semantic types before target projection. */
class M14RuntimeTypeOperandsIntegrationTest {
	/** Uses normal indexed typing so assertions cover the shared compiler boundary. */
	static function typeSource(source:String):TypedModule {
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		return TyperStage.typeResolvedModule(resolved, index, loader);
	}

	/** Selects the actual returned expression rather than trusting its declared result type. */
	static function returned(module:TypedModule, name:String):TypedExpr {
		for (owner in module.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getOwnerName() == "Main" && HxFunctionDecl.getName(fn.getSourceDeclaration()) == name)
					for (statement in fn.getBody().getStatements())
						if (statement.getTag().match(Return))
							return statement.getExpressions()[0];
		throw "missing returned expression: " + name;
	}

	static function main():Void {
		final module = typeSource('class Parent {} class Child extends Parent {}
class Main {
 static function check(child:Parent):Bool { return child is Parent; }
 static function classValue():Class<Parent> { return Parent; }
 static function localValue(Parent:Class<Parent>):Class<Parent> { return Parent; }
}');
		final test = returned(module, "check");
		if (test.getType().getSemanticKey() != "primitive:Bool")
			throw "runtime type test must produce Bool, got " + test.getType().getSemanticKey();
		final classValue = returned(module, "classValue");
		final expected = TyType.nominal(new TyNominalTypeId("Class"), [TyType.nominal(new TyNominalTypeId("Main.Parent"), [])]);
		if (classValue.getType().getSemanticKey() != expected.getSemanticKey())
			throw "class value must retain Class<Main.Parent>, got " + classValue.getType().getSemanticKey();
		if (!returned(module, "localValue").getTag().match(LocalRead))
			throw "a same-spelled lexical class value must remain a local read";
		final core = typeSource('class Main {
 static function arrayType():Class<Array<Dynamic>> { return Array; }
 static function stringType():Class<String> { return String; }
 static function arrayCheck(value:Array<Int>):Bool { return value is Array; }
 static function stringCheck(value:String, String:Int):Bool { return value is String; }
 static function stringLocal(String:Int):Int { return String; }
}');
		for (entry in [
			{name: "arrayType", key: "runtime-core:Array", type: "nominal:Class<nominal:Array<dynamic>>"},
			{name: "stringType", key: "runtime-core:String", type: "nominal:Class<primitive:String>"}
		]) {
			final value = returned(core, entry.name);
			if (!value.getTag().match(RuntimeTypeValue)
				|| value.getRuntimeTypeTarget().getSemanticKey() != entry.key
				|| value.getType().getSemanticKey() != entry.type)
				throw "core class value lost its explicit target or meta-type: " + entry.name;
		}
		for (name in ["arrayCheck", "stringCheck"])
			if (!returned(core, name).getTag().match(RuntimeTypeTest))
				throw "core is operand lost its type namespace: " + name;
		if (!returned(core, "stringLocal").getTag().match(LocalRead))
			throw "core class fallback replaced an ordinary local";
		Sys.println("RUNTIME_TYPE_OPERANDS:PASS");
	}
}
