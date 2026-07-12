import HxExpr;
import haxe.ds.StringMap;

typedef CppEqualityArgFixture = {
	var scope:backend.cpp.CppRenderScope;
}

/**
	Focused attribution probe for C++ equality argument rendering.

	Strict Cpp timing identifies an exact String literal on the right side of a
	typed equality helper as a stable cost. This probe separates direct literal
	rendering, String adaptation, equality-comparable adaptation, and complete
	equality arguments while retaining nonliteral conversion controls.
**/
class M14CppEqualityArgBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 250;

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null || StringTools.trim(raw).length == 0)
			return fallback;
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function fixture():CppEqualityArgFixture {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		final stringAlias = new HxClassDecl("StringAlias", false, [], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=String"]);
		final owner = new HxClassDecl("EqualityArgBenchOwner", false, [], []);
		for (cls in [stringAlias, owner]) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		for (i in 0...280) {
			final cls = new HxClassDecl("EqualityArgDummy" + i, false, [], []);
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: all}, "void");
		for (name in [
			"typedText",
			"dynamicText",
			"aliasText",
			"optionalText",
			"block",
			"items",
			"unknown"
		])
			scope.localNames.set(name, name);
		scope.localTypes.set("typedText", "std::string");
		scope.localTypes.set("dynamicText", "std::any");
		scope.localTypes.set("aliasText", "std::string");
		scope.localTypes.set("optionalText", "std::optional<std::string>");
		scope.localTypes.set("block", "std::shared_ptr<EReg>");
		scope.localTypes.set("items", "std::vector<std::string>");
		scope.localTypes.set("unknown", "std::any");
		scope.localTypeHints.set("typedText", "String");
		scope.localTypeHints.set("dynamicText", "Dynamic");
		scope.localTypeHints.set("aliasText", "StringAlias");
		scope.localTypeHints.set("optionalText", "Null<String>");
		return {scope: scope};
	}

	static function elapsed(calls:Int, action:Void->Void):Float {
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function elapsedNamed(name:String, calls:Int, action:Void->Void):Float {
		action();
		final only = Sys.getEnv("HXHX_CPP_EQUALITY_ARG_BENCH_ONLY");
		if (only != null && StringTools.trim(only).length > 0 && only != name)
			return -1.;
		return elapsed(calls, action);
	}

	static function main():Void {
		final calls = envInt("HXHX_CPP_EQUALITY_ARG_BENCH_CALLS", DEFAULT_CALLS);
		final scope = fixture().scope;
		final literal = EString('{ test } "quoted"\nnext');
		final concat = EBinop("+", EString("prefix:"), EIdent("typedText"));
		final freshMap = ECall(EField(ENew("EReg", [EString("z?"), EString("g")]), "map"),
			[EString("ab"), ELambda(["r"], ECall(EField(EIdent("r"), "matched"), [EInt(0)]))]);
		final typedMatched = ECall(EField(EIdent("block"), "matched"), [EInt(0)]);
		final typedMatchedLeft = ECall(EField(EIdent("block"), "matchedLeft"), []);
		final typedMatchedRight = ECall(EField(EIdent("block"), "matchedRight"), []);
		final typedMap = ECall(EField(EIdent("block"), "map"), [EString("ab"), ELambda(["r"], ECall(EField(EIdent("r"), "matchedLeft"), []))]);
		final freshReplace = ECall(EField(ENew("EReg", [EString("z?"), EString("g")]), "replace"), [EString("ab"), EString("x")]);
		final matchedPosField = EField(ECall(EField(EIdent("block"), "matchedPos"), []), "pos");
		final splitLength = EField(ECall(EField(EIdent("block"), "split"), [EString("a")]), "length");

		var directLiteralSample = "";
		final directLiteralSeconds = elapsedNamed("direct_literal", calls, () -> {
			directLiteralSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(literal, scope);
		});
		var stringLiteralSample = "";
		final stringLiteralSeconds = elapsedNamed("string_literal", calls, () -> {
			stringLiteralSample = @:privateAccess backend.cpp.CppTargetCore.stringExpr(literal, scope);
		});
		var comparableLiteralSample = "";
		final comparableLiteralSeconds = elapsedNamed("comparable_literal", calls, () -> {
			comparableLiteralSample = @:privateAccess
				backend.cpp.CppTargetCore.eqComparableArgExpr(literal, "std::string", "std::string", scope);
		});
		var concatEqualitySample = "";
		final concatEqualitySeconds = elapsedNamed("concat", calls, () -> {
			concatEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([concat, literal], scope).join(", ");
		});
		var freshMapEqualitySample = "";
		final freshMapEqualitySeconds = elapsedNamed("fresh_map", calls, () -> {
			freshMapEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([freshMap, EString("mapped")], scope).join(", ");
		});
		var typedMatchedEqualitySample = "";
		final typedMatchedEqualitySeconds = elapsedNamed("typed_matched", calls, () -> {
			typedMatchedEqualitySample = @:privateAccess
				backend.cpp.CppTargetCore.renderEqCallArgs([typedMatched, EString("capture")], scope).join(", ");
		});
		var typedSideEqualitySample = "";
		final typedSideEqualitySeconds = elapsedNamed("typed_side", calls, () -> {
			typedSideEqualitySample = @:privateAccess
				backend.cpp.CppTargetCore.renderEqCallArgs([typedMatchedLeft, EString("left")], scope)
					.join(", ") + "|" + @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([typedMatchedRight, EString("right")], scope).join(", ");
		});
		var typedMapEqualitySample = "";
		final typedMapEqualitySeconds = elapsedNamed("typed_map", calls, () -> {
			typedMapEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([typedMap, EString("mapped")], scope).join(", ");
		});
		var freshReplaceEqualitySample = "";
		final freshReplaceEqualitySeconds = elapsedNamed("fresh_replace", calls, () -> {
			freshReplaceEqualitySample = @:privateAccess
				backend.cpp.CppTargetCore.renderEqCallArgs([freshReplace, EString("replaced")], scope).join(", ");
		});
		var matchedPosEqualitySample = "";
		final matchedPosEqualitySeconds = elapsedNamed("matched_pos", calls, () -> {
			matchedPosEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([matchedPosField, EInt(0)], scope).join(", ");
		});
		var typedMapDirectEqSample = "";
		final typedMapDirectEqSeconds = elapsedNamed("typed_map_direct_eq", calls, () -> {
			typedMapDirectEqSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("eq", [typedMap, EString("mapped")], scope);
		});
		var splitLengthInferSample = "";
		final splitLengthInferSeconds = elapsedNamed("split_length_infer", calls, () -> {
			splitLengthInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(splitLength, scope);
		});
		var splitLengthPredicateSample = false;
		final splitLengthPredicateSeconds = elapsedNamed("split_length_predicate", calls, () -> {
			splitLengthPredicateSample = @:privateAccess backend.cpp.CppTargetCore.isCppVectorLengthExpr(splitLength, scope);
		});
		var splitLengthRenderSample = "";
		final splitLengthRenderSeconds = elapsedNamed("split_length_render", calls, () -> {
			splitLengthRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(splitLength, scope);
		});
		var splitLengthEqualitySample = "";
		final splitLengthEqualitySeconds = elapsedNamed("split_length_equality", calls, () -> {
			splitLengthEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([splitLength, EInt(1)], scope).join(", ");
		});

		final typedEqualitySample = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs([EIdent("typedText"), EString("typed")], scope).join(", ");
		final dynamicEqualitySample = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs([EIdent("dynamicText"), EString("dynamic")], scope).join(", ");
		final abstractEqualitySample = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs([EIdent("aliasText"), EString("alias")], scope).join(", ");
		final optionalEqualitySample = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs([EIdent("optionalText"), ENull], scope).join(", ");
		var optionalEqualityTimedSample = "";
		final optionalEqualitySeconds = elapsedNamed("optional", calls, () -> {
			optionalEqualityTimedSample = @:privateAccess
				backend.cpp.CppTargetCore.renderEqCallArgs([EIdent("optionalText"), ENull], scope).join(", ");
		});
		var dynamicEqualityTimedSample = "";
		final dynamicEqualitySeconds = elapsedNamed("dynamic", calls, () -> {
			dynamicEqualityTimedSample = @:privateAccess
				backend.cpp.CppTargetCore.renderEqCallArgs([EIdent("dynamicText"), EString("dynamic")], scope).join(", ");
		});
		final numericEqualitySample = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs([EInt(1), EInt(2)], scope).join(", ");
		final unknownLength = EField(ECall(EField(EIdent("unknown"), "split"), [EString("a")]), "length");
		final wrongArityLength = EField(ECall(EField(EIdent("block"), "split"), []), "length");
		final wrongMethodLength = EField(ECall(EField(EIdent("block"), "map"), [EString("a")]), "length");
		final vectorLength = EField(EIdent("items"), "length");
		final declineSample = [unknownLength, wrongArityLength, wrongMethodLength].map(expr -> @:privateAccess
			backend.cpp.CppTargetCore.inferExprCppType(expr, scope)).join(",");
		final vectorLengthInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(vectorLength, scope);

		assertTrue(directLiteralSample == '"{ test } \\"quoted\\"\\nnext"', "direct String literals should retain their escaped token");
		assertTrue(stringLiteralSample == "std::string(" + directLiteralSample + ")",
			"String adaptation should retain the std::string carrier, got " + stringLiteralSample);
		assertTrue(comparableLiteralSample == stringLiteralSample,
			"typed String equality literals should retain String adaptation, got " + comparableLiteralSample);
		assertTrue(concatEqualitySample == '(std::string("prefix:") + std::string(typedText)), ' + stringLiteralSample,
			"typed concat equality should retain exact comparable arguments, got " + concatEqualitySample);
		assertTrue(freshMapEqualitySample == 'std::make_shared<EReg>("z?", "g")->map("ab", [&](std::shared_ptr<EReg> r) -> std::string { return r->matched(0).value_or(std::string()); }), std::string("mapped")',
			"fresh EReg equality should retain its target-owned String result, got "
			+ freshMapEqualitySample);
		assertTrue(typedMatchedEqualitySample == 'block->matched(0), std::string("capture")'
			&& typedSideEqualitySample == 'block->matchedLeft(), std::string("left")|block->matchedRight(), std::string("right")',
			"typed EReg capture equality should preserve indexed and side-capture contracts");
		assertTrue(typedMapEqualitySample == 'block->map("ab", [&](std::shared_ptr<EReg> r) -> std::string { return r->matchedLeft(); }), std::string("mapped")'
			&& typedMapDirectEqSample == "eq("
			+ typedMapEqualitySample
			+ ")",
			"typed EReg map equality should preserve exact argument and direct-call output");
		assertTrue(freshReplaceEqualitySample == 'std::make_shared<EReg>("z?", "g")->replace("ab", "x"), std::string("replaced")',
			"fresh EReg replace equality should preserve its fixed String result");
		assertTrue(matchedPosEqualitySample == "(block->matchedPos().pos), 0",
			"typed EReg matched-position equality should preserve its fixed Int field, got " + matchedPosEqualitySample);
		final reversedTypedMapSample = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs([EString("mapped"), typedMap, EInt(7)], scope).join(", ");
		final nonliteralTypedMapSample = @:privateAccess
			backend.cpp.CppTargetCore.renderEqCallArgs([typedMap, EIdent("typedText")], scope).join(", ");
		assertTrue(reversedTypedMapSample == 'std::string("mapped"), block->map("ab", [&](std::shared_ptr<EReg> r) -> std::string { return r->matchedLeft(); }), 7'
			&& nonliteralTypedMapSample == 'block->map("ab", [&](std::shared_ptr<EReg> r) -> std::string { return r->matchedLeft(); }), std::string(typedText)'
			&& typedMatchedEqualitySample == 'block->matched(0), std::string("capture")',
			"EReg String equality controls should preserve reversal, extras, nonliteral peers, and nullable indexed captures");
		assertTrue(typedEqualitySample == 'std::string(typedText), std::string("typed")',
			"typed String locals should retain normal equality adaptation, got " + typedEqualitySample);
		assertTrue(dynamicEqualitySample == '__hxhx_stringify(dynamicText), std::string("dynamic")',
			"Dynamic values should retain runtime String conversion, got " + dynamicEqualitySample);
		assertTrue(abstractEqualitySample == 'std::string(aliasText), std::string("alias")',
			"String-backed abstracts should retain their equality conversion, got " + abstractEqualitySample);
		assertTrue(optionalEqualitySample == 'optionalText.value(), std::optional<std::string>{}',
			"optional String equality should retain its empty optional carrier, got " + optionalEqualitySample);
		assertTrue(optionalEqualityTimedSample == optionalEqualitySample && dynamicEqualityTimedSample == dynamicEqualitySample,
			"timed optional and Dynamic equality controls should retain their exact outputs");
		assertTrue(numericEqualitySample == "1, 2", "numeric equality should remain outside String adaptation");
		assertTrue(splitLengthPredicateSample, "typed-local EReg split length should retain its exact vector-length predicate");
		assertTrue(splitLengthInferSample == "int", "typed-local EReg split length should expose its exact Int type");
		assertTrue(splitLengthRenderSample == '(block->split("a").size())',
			"typed-local EReg split length should retain exact rendering, got " + splitLengthRenderSample);
		assertTrue(splitLengthEqualitySample == 'static_cast<int>((block->split("a").size())), 1',
			"typed-local EReg split length equality should retain exact adaptation, got " + splitLengthEqualitySample);
		assertTrue(declineSample == ",," && vectorLengthInferSample == "",
			"unknown, wrong-arity, wrong-method, and ordinary vector lengths should retain general inference, got decline="
			+ declineSample
			+ " vector="
			+ vectorLengthInferSample);

		Sys.println("CPP_EQUALITY_ARG_BENCH:PASS calls=" + calls + " direct_literal_seconds=" + directLiteralSeconds + " string_literal_seconds="
			+ stringLiteralSeconds + " comparable_literal_seconds=" + comparableLiteralSeconds + " concat_equality_seconds=" + concatEqualitySeconds
			+ " fresh_map_equality_seconds=" + freshMapEqualitySeconds + " typed_matched_equality_seconds=" + typedMatchedEqualitySeconds
			+ " typed_side_equality_seconds=" + typedSideEqualitySeconds + " typed_map_equality_seconds=" + typedMapEqualitySeconds
			+ " fresh_replace_equality_seconds=" + freshReplaceEqualitySeconds + " matched_pos_equality_seconds=" + matchedPosEqualitySeconds
			+ " optional_equality_seconds=" + optionalEqualitySeconds + " dynamic_equality_seconds=" + dynamicEqualitySeconds
			+ " typed_map_direct_eq_seconds=" + typedMapDirectEqSeconds);
		Sys.println("CPP_SPLIT_LENGTH_INFER_BENCH:PASS calls=" + calls + " infer_seconds=" + splitLengthInferSeconds + " predicate_seconds="
			+ splitLengthPredicateSeconds + " render_seconds=" + splitLengthRenderSeconds + " equality_seconds=" + splitLengthEqualitySeconds
			+ " inferred_type=" + splitLengthInferSample);
	}
}
