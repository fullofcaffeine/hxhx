/** Quoted data retains exact enum providers without retaining quoted calls or unrelated module members. */
class M14QuotationEnumDependenciesTest {
	public static function run():Void {
		final source = "enum Constant { Number(value:Int); } enum Other { Ready; } enum Unused { Never; } "
			+ "enum ExprData<T> { Literal(value:Constant); Child(value:Quote<T>); Payload(value:T); } "
			+ "typedef Growth<T> = {entry:Constant, next:Null<Growth<{value:T}>>}; "
			+ "typedef Quote<T> = {expr:ExprData<T>, growth:Growth<T>}; "
			+ "class Main { static var schema:Quote<Other>; static function main():Void {} static function unused():Void {} }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final providers = new haxe.ds.StringMap<TypedClass>();
		for (owner in typed.getTypedClasses())
			providers.set(owner.getSemanticInfo().getIdentity().getCanonicalName(), owner);
		final main = providers.get("Main");
		final type = main.getSemanticInfo().fieldInfo("schema").getType();
		final expected = ["Main.Constant", "Main.ExprData", "Main.Other"];
		final found = TypedQuotationEnumDependencies.find(type, providers);
		assertNames(found, expected);
		// This unbound callable would be rejected if reference closure entered the quote.
		final quoted = TypedExpr.macroExpr(TypedExpr.nameRead("doNotExecute", TyType.fromHintText("Void->Void"), null), [], type, null);
		final original = main.getFunctions().filter(fn -> fn.getDeclaration().getSignature().getName() == "main")[0];
		final entry = original.withBody(new TypedFunctionBody([TypedStmt.expressionStmt(quoted, null)], original.getBody().getSourceFingerprint()));
		final replacement = main.withFunctions([entry].concat(main.getFunctions().filter(fn -> fn != original)));
		final module = typed.withTypedClasses([for (owner in typed.getTypedClasses()) owner == main ? replacement : owner]);
		final program = new MacroExpandedProgram([module], false);
		final reachable = TypedFeatureMemberClosure.retain({
			program: program,
			classes: [],
			functions: [entry],
			fields: []
		});
		assertNames(reachable.classes, ["Main"].concat(expected));
		if (reachable.functions.length != 1 || reachable.functions[0] != entry || reachable.fields.length != 0)
			throw "quotation retained executable members from its representation or source";
		final retained = new TypedEmissionRetention({reachable: reachable, mode: "full"}).apply(program);
		final plan = new backend.js.JsClassInheritancePlan(retained);
		for (identity in expected)
			if (plan.requireRuntimeEnum(identity).identity != identity)
				throw "quotation enum lost its exact provider during emission retention";
		providers.remove("Main.Constant");
		var diagnostic = "";
		try {
			TypedQuotationEnumDependencies.find(type, providers);
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic != "quotation type has no exact program provider: Main.Constant")
			throw "quotation dependency accepted an absent exact provider: " + diagnostic;
		Sys.println("QUOTATION_ENUM_DEPENDENCIES:PASS");
	}

	static function assertNames(classes:Array<TypedClass>, expected:Array<String>):Void {
		final actual = classes.map(owner -> owner.getSemanticInfo().getIdentity().getCanonicalName());
		actual.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (actual.join(",") != expected.join(","))
			throw "quotation representation dependencies differ: " + actual.join(",");
	}
}
