import TypedExpr.TypedExprTag;

/**
	Checks catch types and declaration identities before any target lowers them.
	The empty exception declaration supplies nominal identity only; real exception
	construction and wrapping belong to the separate provider runtime fixture.
**/
class M14TypedCatchBindingIntegrationTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function checkExpression(expression:TypedExpr, expected:TyLocalBinding):Void {
		if (expression.getTag() == LocalRead && expression.getTexts()[0] == "error") {
			final bindings = expression.getLocalBindings();
			require(bindings.length == 1
				&& bindings[0].getIdentity().equals(expected.getIdentity()), "catch read lost declaration identity");
			require(expression.getType().getSemanticKey() == expected.getType().getSemanticKey(), "catch read lost declared type");
		}
		for (child in expression.getExpressions())
			checkExpression(child, expected);
	}

	static function checkStatement(statement:TypedStmt, expected:TyLocalBinding):Void {
		for (expression in statement.getExpressions())
			checkExpression(expression, expected);
		for (child in statement.getStatements())
			checkStatement(child, expected);
	}

	static function main():Void {
		final source = [
			"class Main {",
			"static function expressionInt() { final value = try 1 catch(error:Int) error; }",
			"static function statementInt() { try { throw 1; } catch(error:Int) { final value = error; } }",
			"static function expressionException() { final value = try null catch(error:haxe.Exception) error; }",
			"static function statementException() { try { throw 'problem'; } catch(error:haxe.Exception) { final value = error; } }",
			"static function expressionOmitted() { final value = try null catch(error) error; }",
			"static function statementOmitted() { try { throw 'problem'; } catch(error) { final value = error; } }",
			"static function captureInt() { final value = try 1 catch(error:Int) (() -> error)(); }",
			"static function nestedInt() { final value = try 1 catch(outer:Int) (try 2 catch(error:Int) error + outer); }",
			"static function nestedBlockInt() { final value = try 1 catch(outer:Int) { final inner = try 2 catch(error:Int) error + outer; inner; }; }",
			"}",
		].join("\n");
		final main = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final exception = new ResolvedModule("haxe.Exception", "haxe/Exception.hx", ParserStage.parse("package haxe; class Exception {}", "haxe/Exception.hx"));
		final index = TyperIndex.build([main, exception]);
		final module = TyperStage.typeResolvedModule(main, index);
		var exceptionKey:Null<String> = null;
		for (functionValue in module.getTypedClasses()[0].getFunctions()) {
			final name = HxFunctionDecl.getName(functionValue.getSourceDeclaration());
			final bindings = [
				for (symbol in functionValue.getEnvironment().getLocals())
					if (symbol.getName() == "error") symbol.toBinding()
			];
			require(bindings.length == 1, name + ": expected one catch declaration; locals=" + [
				for (symbol in functionValue.getEnvironment().getLocals())
					symbol.getName() + ":" + symbol.getKind()
			].join(","));
			final binding = bindings[0];
			require(binding.getKind() == CatchVariable, name + ": catch recorded as " + binding.getKind());
			if (name.indexOf("Int") >= 0) {
				require(binding.getType().getSemanticKey() == "primitive:Int", name + ": lost Int catch type");
			} else {
				require(binding.getType().getNominalIdentity() != null, name + ": catch is not a resolved nominal type");
				require(binding.getType().getNominalIdentity().getCanonicalName() == "haxe.Exception", name + ": catch selected the wrong exception class");
				if (exceptionKey == null)
					exceptionKey = binding.getType().getSemanticKey();
				require(binding.getType().getSemanticKey() == exceptionKey, name + ": omitted and explicit exception catches disagree");
			}
			for (statement in functionValue.getBody().getStatements())
				checkStatement(statement, binding);
			final projection = TypedBodySource.functionProjection(functionValue);
			final projected = [
				for (entry in projection.getLocalCatalog().getEntries())
					if (entry.getBinding().getIdentity().equals(binding.getIdentity())) entry
			];
			require(projected.length == 1
				&& projected[0].getBinding().getKind() == CatchVariable, name + ": backend projection lost the catch declaration");
		}
		final lambdaModule = TyperStage.typeModule(ParserStage.parse("class LambdaControl { static function run() { final f = argument -> argument; } }",
			"LambdaControl.hx"));
		final lambdaLocals = lambdaModule.getTypedClasses()[0].getFunctions()[0].getEnvironment().getLocals();
		require(lambdaLocals[0].getKind() == LambdaParameter, "ordinary lambda parameter became a catch declaration");
		Sys.println("TYPED_CATCH_BINDING:PASS");
	}
}
