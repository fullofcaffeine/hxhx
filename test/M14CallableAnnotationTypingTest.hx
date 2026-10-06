/**
 * Checks callable results before target rendering can hide a lost annotation.
 * Written Dynamic storage must remain erased when later callbacks return other values.
 */
class M14CallableAnnotationTypingTest {
	static function statements(body:String):Array<TypedStmt> {
		final source = "class CallableFixture { static function probe():Void { " + body + " } }";
		final resolved = new ResolvedModule("CallableFixture", "CallableFixture.hx", ParserStage.parse(source, "CallableFixture.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		return typed.getTypedClasses()[0].getFunctions()[0].getBody().getStatements();
	}

	static function resultType(statement:TypedStmt):String {
		final type = statement.getExpressions()[0].getType();
		return type.isFunction() ? type.getFunctionReturn().getDisplay() : "not callable: " + type.getDisplay();
	}

	static function requireResult(body:String, expected:String):Void {
		final actual = resultType(statements(body)[0]);
		if (actual != expected)
			throw "Expected " + expected + ", got " + actual;
	}

	static function requireRejected(body:String, ?diagnostic:String):Void {
		var rejected = false;
		try {
			statements(body);
		} catch (error:TyperError) {
			if (diagnostic != null && error.toString().indexOf(diagnostic) < 0)
				throw "Expected diagnostic " + diagnostic + ", got " + error.toString();
			rejected = true;
		}
		if (!rejected)
			throw "Invalid callback was accepted: " + body;
	}

	static function requireSignatureFacts():Void {
		final omitted = HxParser.parseCompleteExprText("function(value:String) return value");
		final written = HxParser.parseCompleteExprText("function(value:String):Dynamic return value");
		switch ([omitted, written]) {
			case [ELambda(_, _, inferred), ELambda(_, _, explicit)]:
				if (inferred == null
					|| explicit == null
					|| inferred.getReturnTypeHint() != null
					|| explicit.getReturnTypeHint() != "Dynamic")
					throw "Parser lost return annotation absence";
				if (inferred.getParameters()[0].typeHint != "String")
					throw "Parser lost the parameter annotation";
			case _:
				throw "Function annotations must belong to ELambda";
		}
		if (TypedBodyFingerprint.forExpression(omitted) == TypedBodyFingerprint.forExpression(written))
			throw "Annotation-only source edit did not change the fingerprint";
		switch (HxParser.parseCompleteExprText("function(value:Int = 2, ?extra:String) return value")) {
			case ECall(EIdent("__hxhx_optional_lambda"), [ELambda(_, _, signature), _]):
				final parameters = signature.getParameters();
				if (!parameters[0].hasDefault || !parameters[0].isOptional || parameters[1].hasDefault || !parameters[1].isOptional)
					throw "Default and optional declaration facts were merged";
			case _:
				throw "Default/optional wrapper lost the lambda signature";
		}
		final named = HxParser.parseFunctionBodyText("function f(value:String):Dynamic return value;");
		switch (named[0]) {
			case SVar(_, "", ELambda(_, _, signature), _) if (signature.getReturnTypeHint() == "Dynamic"):
			case _:
				throw "Named function fabricated a local storage annotation";
		}
	}

	static function requireProjectionAndRevision():Void {
		final omitted = statements("var f = function(value:String) return value;")[0];
		final written = statements("var f = function(value:String):String return value;")[0];
		final inferredLambda = omitted.getExpressions()[0];
		final explicitLambda = written.getExpressions()[0];
		if (inferredLambda.getType().getSemanticKey() != explicitLambda.getType().getSemanticKey())
			throw "Equivalent inferred and written result types differ";
		if (CompilerTypedTreeRevision.expression("fixture", inferredLambda) == CompilerTypedTreeRevision.expression("fixture", explicitLambda))
			throw "Annotation-only edit did not change the typed revision";
		for (rebuilt in [
			explicitLambda.withExpressions(explicitLambda.getExpressions()),
			explicitLambda.withType(explicitLambda.getType()),
			explicitLambda.withCatchUses(explicitLambda.getCatchUses())
		]) {
			if (rebuilt.getLambdaSignature() == null || rebuilt.getLambdaSignature().getReturnTypeHint() != "String")
				throw "Immutable rebuild lost the annotation";
		}
		switch (TypedBodySource.expression(inferredLambda)) {
			case ECast(ELambda(_, _, signature), "(String)->String") if (signature.getReturnTypeHint() == null):
			case _:
				throw "Projection must carry the selected type and preserve source omission";
		}
		final storage = statements('var f:String->Dynamic = function(value:String) return value;')[0];
		switch (TypedBodySource.statement(storage)) {
			case SVar(_, "(String)->Dynamic", ECast(_, "(String)->String"), _):
			case _:
				throw "Projection merged destination storage with implementation type";
		}
	}

	/** Result conversion must preserve catch-runtime dependencies and source annotations. */
	static function requireCatchConversionFacts():Void {
		final dynamicType = TyType.fromHintText("Dynamic");
		final stringType = TyType.fromHintText("String");
		final binding = new TyLocalBinding(TyLocalId.forSourceDeclaration("catch-fixture", 0, CatchVariable, "caught"), "caught", dynamicType, CatchVariable);
		final context = new TyperContext(TyperIndex.build([]), "Catch.hx", "Catch", "", [], "Catch");
		final use = TypedCatchUse.resolve(binding, context);
		final signature = new HxLambdaSignature([
			{
				typeHint: "Dynamic",
				isOptional: false,
				isRest: false,
				hasDefault: false
			}
		], "Dynamic");
		final handler = TypedExpr.lambda(["caught"], TypedExpr.localRead("caught", dynamicType, null, binding),
			TyType.functionType([dynamicType], dynamicType), null, [binding], signature)
			.withCatchUses([use]);
		final text = TypedExpr.stringLiteral("value", stringType, null);
		final entry = TypedExpr.arrayDecl([
			TypedExpr.stringLiteral("caught", stringType, null),
			TypedExpr.stringLiteral("Dynamic", stringType, null),
			handler
		], dynamicType, null);
		final arguments = [
			TypedExpr.lambda([], text, TyType.functionType([], stringType), null),
			TypedExpr.arrayDecl([entry], dynamicType, null),
			text
		];
		final aligned = @:privateAccess TypedBodyBuilder.alignStructuralTryCatchResults(arguments, stringType);
		final converted = aligned[1].getExpressions()[0].getExpressions()[2];
		if (converted.getCatchUses().length != 1 || converted.getCatchUses()[0].getCanonicalIdentity() != use.getCanonicalIdentity())
			throw "Catch result conversion dropped its runtime dependency facts";
		if (converted.getLambdaSignature() != signature || converted.getLocalBindings()[0] != binding)
			throw "Catch result conversion replaced its annotation or binding identity";
		if (converted.getType().getFunctionReturn().getDisplay() != "String" || converted.getExpressions()[0].getTag() != Cast)
			throw "Catch result conversion did not expose the selected String result";
	}

	public static function run():Void {
		final previousStrict = Sys.getEnv("HXHX_TYPER_STRICT");
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		final failures = new Array<String>();
		function check(name:String, run:Void->Void):Void {
			try {
				run();
			} catch (error:TyperError) {
				failures.push(name + ": " + error.toString());
			} catch (error:String) {
				failures.push(name + ": " + error);
			}
		}
		check("omitted anonymous", () -> requireResult("var f = function(v:String) return v;", "String"));
		check("explicit anonymous", () -> requireResult("var f = function(v:String):Dynamic return v;", "Dynamic"));
		check("omitted named", () -> requireResult("function f(v:String) return v;", "String"));
		check("explicit named", () -> requireResult("function f(v:String):Dynamic return v;", "Dynamic"));
		check("optional wrapper", () -> requireResult("function f(v:String, ?extra:String) return v;", "String"));
		check("rest wrapper", () -> requireResult("function f(v:String, ...extra:String) return v;", "String"));
		check("empty omitted", () -> requireResult("var f = function() {};", "Void"));
		check("empty explicit Void", () -> requireResult("var f = function():Void {};", "Void"));
		check("explicit Void rejects value", () -> requireRejected("var f = function():Void return 7;", "Int is not compatible with Void"));
		check("partial Dynamic return", () -> requireRejected("var f = function(flag:Bool):Dynamic { if (flag) return 7; };", "Missing return: Dynamic"));
		check("complete Dynamic branches", () -> requireResult("var f = function(flag:Bool):Dynamic { if (flag) return 7; else return 8; };", "Dynamic"));
		check("partial return after local",
			() -> requireRejected("var f = function(flag:Bool):Dynamic { var value = 7; if (flag) return value; };", "Missing return: Dynamic"));
		check("complete return after local",
			() -> requireResult("var f = function(flag:Bool):Int { var value = 7; if (flag) return value; else return 8; };", "Int"));
		check("branch mismatch after local",
			() -> requireRejected('var f = function(flag:Bool):Int { var value = "bad"; if (flag) return value; else return 8; };',
				"String is not compatible with Int"));
		check("nested callback owns result", () -> requireResult("var f = function():Void { var inner = function():Int return 7; inner(); };", "Void"));
		check("Void rejects Dynamic", () -> requireRejected("var f = function(value:Dynamic):Void return value;", "Dynamic is not compatible with Void"));
		check("Void rejects null", () -> requireRejected("var f = function():Void return null;", "is not compatible with Void"));
		check("Void allows Void call", () -> requireResult('var f = function():Void return Sys.println("effect");', "Void"));
		check("throw has no return obligation", () -> requireResult('var f = function():Dynamic { throw "boom"; };', "Dynamic"));
		check("partial try return",
			() -> requireRejected("var f = function(flag:Bool):Dynamic { try { if(flag) return 7; } catch (e:Dynamic) { return 8; } };",
				"Missing return: Dynamic"));
		check("throw then catch result",
			() -> requireResult('var f = function():String { try { throw "boom"; } catch (e:Dynamic) { return "caught"; } };', "String"));
		check("constant if still needs return", () -> requireRejected("var f = function():Dynamic { if(true) return 7; };", "Missing return: Dynamic"));
		check("complete switch result",
			() -> requireResult("var f = function(value:Int):Int { switch(value) { case 0: return 7; default: return 8; } };", "Int"));
		check("partial switch result",
			() -> requireRejected("var f = function(value:Int):Dynamic { switch(value) { case 0: return 7; } };", "Missing return: Dynamic"));
		check("null is a result", () -> requireResult("var f = function():Dynamic return null;", "Dynamic"));
		check("missing Dynamic result", () -> requireRejected("var f = function():Dynamic {};"));
		check("discarded Dynamic result", () -> requireRejected('var f = function():Dynamic { Sys.println("effect"); };'));
		check("inferred storage rejects Int", () -> requireRejected("var f = function(v:String) return v; f = function(v:String) return 7;"));
		check("written storage stays Dynamic", () -> {
			final body = 'var f:String->Dynamic = function(v:String):Dynamic return v;
f = function(v:String) return 7;
f = function(v:String) return true;
f = function(v:String) return null;
var selected = f;';
			final values = statements(body);
			if (resultType(values[4]) != "Dynamic")
				throw "Reassignment narrowed the callback storage";
		});
		check("parser provenance", requireSignatureFacts);
		check("typed projection and revision", requireProjectionAndRevision);
		check("catch conversion facts", requireCatchConversionFacts);
		check("unknown argument stays unresolved", () -> {
			final lambda = statements('var f = function(value) return "text";')[0].getExpressions()[0];
			if (!lambda.getType().getFunctionArguments()[0].isUnknown() || !lambda.getType().hasUnknownComponent())
				throw "An omitted unconstrained parameter became Dynamic";
			switch (TypedBodySource.expression(lambda)) {
				case ELambda(_, _, _):
				case _: throw "An incomplete function type became a complete source-shaped ascription";
			}
		});
		Sys.putEnv("HXHX_TYPER_STRICT", previousStrict == null ? "" : previousStrict);
		if (failures.length > 0)
			throw failures.join("\n");
		Sys.println("CALLABLE_ANNOTATION_TYPING:PASS");
	}

	static function main():Void
		run();
}
