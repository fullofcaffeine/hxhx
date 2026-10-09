/** Applied abstract arguments must authorize and preserve only their declared conversions. */
class M14GenericAbstractConversionTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	/** Compare the authored program with upstream and execute the shared typed result in Node. */
	static function checkRuntime():Void {
		final fixture = "test/generic_abstract_inputs";
		final expected = StringTools.trim(sys.io.File.getContent(fixture + "/expected.stdout"));
		final upstream = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("haxe", ["-cp", fixture, "-main", "Main", "--interp"]);
		require(StringTools.trim(upstream) == expected, "upstream generic conversion output changed");
		final path = fixture + "/Main.hx";
		final program = JsSourceProgramFixture.build({sources: [{path: "Main.hx", source: sys.io.File.getContent(path)}], requiredModules: ["Array"]});
		final output = ".tmp/generic_abstract_conversion_" + Date.now().getTime();
		final script = @:privateAccess M14PromotionPluginBuiltinEquivalenceIntegrationTest.emitWithBackend(new backend.js.JsBackend(), program, output);
		final actual = @:privateAccess M14PromotionPluginBuiltinEquivalenceIntegrationTest.runNodeScript(script);
		require(actual == expected, "native JavaScript generic conversion output changed: " + actual);
		Sys.println("GENERIC_ABSTRACT_CONVERSION_RUNTIME:PASS");
	}

	static function main():Void {
		final source = "abstract Box<T>(T) from T to T {} abstract Hidden<T>(T) {} abstract Wrong<T>(Bool) from T {}"
			+ "class Carrier<T> {} abstract Nested<T>(Carrier<T>) from Carrier<T> to Carrier<T> {}";
		final parsed = ParserStage.parse(source, "Boundary.hx");
		final index = TyperIndex.build([new ResolvedModule("Boundary", "Boundary.hx", parsed)]);
		final integer = TyType.fromHintText("Int");
		final text = TyType.fromHintText("String");
		final box = TyType.nominal(new TyNominalTypeId("Boundary.Box"), [integer]);
		final input = TyImplicitConversionPlan.select(index, box, integer);
		require(input != null, "generic declared input lost its substituted conversion");
		require(input.isRepresentationPreservingAbstractConversion(), "generic input lost its exact backing type");
		require(input.getViaType().getSemanticKey() == integer.getSemanticKey(), "generic input retained an unbound header type");
		final literal = TypedExpr.intLiteral(7, integer, HxPos.unknown());
		final converted = input.apply(literal);
		var rejectedForeignOperand = false;
		try {
			input.apply(TypedExpr.stringLiteral("wrong", text, HxPos.unknown()));
		} catch (message:String) {
			rejectedForeignOperand = message == "implicit conversion operand differs from its selected source type";
		}
		require(rejectedForeignOperand, "selected conversion accepted a different operand type");
		require(converted.isRepresentationPreservingCast(), "selected conversion lost its storage guarantee");
		require(!converted.withType(text).isRepresentationPreservingCast(), "changed destination kept an unrelated storage guarantee");
		require(!converted.withExpressions([TypedExpr.stringLiteral("wrong", text, HxPos.unknown())]).isRepresentationPreservingCast(),
			"changed operand type kept an unrelated storage guarantee");
		require(converted.withExpressions([TypedExpr.intLiteral(8, integer, HxPos.unknown())]).isRepresentationPreservingCast(),
			"same-type operand replacement lost its storage guarantee");
		final authored = TypedExpr.castValue(literal, box.getDisplay(), box, HxPos.unknown());
		require(!authored.isRepresentationPreservingCast(), "authored cast acquired a compiler conversion guarantee");
		require(CompilerTypedTreeRevision.expression("cast-owner", authored) != CompilerTypedTreeRevision.expression("cast-owner", converted),
			"cast provenance did not change the typed body revision");
		final output = TyImplicitConversionPlan.select(index, integer, box);
		require(output != null && output.isRepresentationPreservingAbstractConversion(), "generic declared output lost its conversion");
		require(TyImplicitConversionPlan.select(index, box, text) == null, "different applied input acquired a conversion");
		require(TyImplicitConversionPlan.select(index, text, box) == null, "different applied output acquired a conversion");
		final hidden = TyType.nominal(new TyNominalTypeId("Boundary.Hidden"), [integer]);
		require(TyImplicitConversionPlan.select(index, hidden, integer) == null, "matching storage authorized an undeclared input");
		final wrong = TyImplicitConversionPlan.select(index, TyType.nominal(new TyNominalTypeId("Boundary.Wrong"), [integer]), integer);
		require(wrong != null && !wrong.isRepresentationPreservingAbstractConversion(), "different backing type became a storage cast");
		final record = TyType.nominal(new TyNominalTypeId("Boundary.Carrier"), [integer]);
		final nested = TyType.nominal(new TyNominalTypeId("Boundary.Nested"), [integer]);
		final nestedInput = TyImplicitConversionPlan.select(index, nested, record);
		require(nestedInput != null
			&& nestedInput.isRepresentationPreservingAbstractConversion(), "nested header substitution lost its input");
		final nestedOutput = TyImplicitConversionPlan.select(index, record, nested);
		require(nestedOutput != null
			&& nestedOutput.isRepresentationPreservingAbstractConversion(), "nested header substitution lost its output");
		checkRuntime();
		Sys.println("GENERIC_ABSTRACT_CONVERSION:PASS");
	}
}
