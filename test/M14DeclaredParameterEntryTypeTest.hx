/** Written call types and nullable body inputs are distinct parts of a declared parameter contract. */
class M14DeclaredParameterEntryTypeTest {
	static function main():Void {
		final source = 'class Main { static function probe<T>(?i:Int, ?s:String, ?t:T, n:Int=4, ?b:Bool):Void {} static function infer(?value):Void { take(value); } static function take(value:Int):Void {} static function rest(...values:Int):Void {} }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final parameters = functions[0].getEnvironment().getParams();
		final expected = [
			"nullable:primitive:Int",
			"nullable:primitive:String",
			null,
			"primitive:Int",
			"nullable:primitive:Bool"
		];
		for (index in 0...parameters.length) {
			final type = parameters[index].getType();
			if (index == 2) {
				if (!type.isNullable() || type.unwrapNull().getTypeParameterIdentity() == null)
					throw "optional generic parameter lost its nullable binder";
			} else if (type.getSemanticKey() != expected[index]) {
				throw "declared parameter body type differs at " + index + ": " + type.getSemanticKey();
			}
		}
		if (functions[0].getDeclaration().getSignature().getArgs()[0].getSemanticKey() != "primitive:Int")
			throw "body nullability changed the written call type";
		if (functions[1].getEnvironment().getParams()[0].getType().getSemanticKey() != "nullable:primitive:Int")
			throw "inference lost optional parameter nullability: " + functions[1].getEnvironment().getParams()[0].getType().getSemanticKey();
		if (functions[3].getEnvironment().getParams()[0].getType().isNullable())
			throw "rest omission incorrectly introduced a nullable body collection";
		Sys.println("DECLARED_PARAMETER_ENTRY_TYPES:PASS");
	}
}
