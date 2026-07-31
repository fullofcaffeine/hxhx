import HxExpr;
import HxStmt;
import TypedExpr.TypedExprTag;
import TypedStmt.TypedStmtTag;

/**
	Proves that shared typed bodies bind local uses by declaration identity.

	The fixture deliberately reuses `value` in a nested block and as a lambda
	parameter. Correctness means each read/update points at the nearest active
	declaration while a capture outside that shadow keeps the outer identity.
**/
class M14TypedLocalIdentityIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function bindingOfStatement(statement:TypedStmt):TyLocalBinding {
		final bindings = statement.getLocalBindings();
		assertTrue(bindings.length == 1, "typed variable statement did not carry exactly one local binding");
		return bindings[0];
	}

	static function bindingOfRead(expression:TypedExpr):TyLocalBinding {
		assertTrue(expression.getTag() == TypedExprTag.LocalRead, "expected a typed local read");
		final bindings = expression.getLocalBindings();
		assertTrue(bindings.length == 1, "typed local read did not carry exactly one local binding");
		return bindings[0];
	}

	static function typedFunction():TypedFunction {
		final position = new HxPos(0, 1, 1);
		final body = [
			SVar("value", "Int", EInt(1), position),
			SVar("before", "Int", EIdent("value"), position),
			SBlock([
				SVar("value", "String", ECast(EIdent("value"), "String"), position),
				SVar("inside", "String", EIdent("value"), position),
				SExpr(EBinop("=", EIdent("value"), EString("changed")), position)
			],
				position),
			SVar("after", "Int", EIdent("value"), position),
			SExpr(EBinop("+=", EIdent("value"), EInt(2)), position),
			SExpr(EUnop(Increment, Postfix, EIdent("value")), position),
			SVar("shadowingLambda", "", ELambda(["value"], EIdent("value")), position),
			SVar("capturingLambda", "", ELambda([], EIdent("value")), position),
			SForIn("item", EArrayDecl([EString("loop")]), SBlock([SVar("loopCopy", "String", EIdent("item"), position)], position), position),
			STry(SBlock([], position), [
				{
					name: "error",
					typeHint: "String",
					body: SBlock([SVar("caught", "String", EIdent("error"), position)], position)
				}
			],
				position),
			SExpr(EVars([HxExprVarDecl.make("expressionLocal", "Int", EInt(7), position)]), position),
			SVar("afterExpression", "Int", EIdent("expressionLocal"), position),
			SVar("comprehension", "", EArrayComprehension("entry", EArrayDecl([EInt(1)]), null, EIdent("entry")), position),
			SExpr(EUnop(Increment, Prefix, EIdent("value")), position),
			SSwitch(EString("pattern"), [PBind("patternValue")], [
				SBlock([SVar("patternCopy", "String", EIdent("patternValue"), position)], position)
			],
				position),
			SSwitch(EArrayDecl([EInt(9), EInt(1)]), [POr([PArray([PBind("orValue"), PInt(1)]), PArray([PInt(1), PBind("orValue")])])],
				[SBlock([SVar("orCopy", "Dynamic", EIdent("orValue"), position)], position)], position),
			SVar("orExpressionResult", "Dynamic", ESwitch(EArrayDecl([EInt(9), EInt(1)]), [
				POr([
					PArray([PBind("orExpressionValue"), PInt(1)]),
					PArray([PInt(1), PBind("orExpressionValue")])
				])
			], [EIdent("orExpressionValue")]), position)
		];
		final sourceFunction = new HxFunctionDecl("check", Public, true, [], "Void", body, "", [], position);
		final sourceClass = new HxClassDecl("LocalIdentity", true, [sourceFunction], []);
		final parsed = new ParsedModule("", new HxModuleDecl("", [], sourceClass, [sourceClass], false, false), "LocalIdentity.hx");
		return TyperStage.typeModule(parsed).getTypedClasses()[0].getFunctions()[0];
	}

	static function temporaryIdentities(owner:String, pass:String):Array<String> {
		final allocator = new TyCompilerTemporaryAllocator(owner, pass, "__fixture_");
		return [
			allocator.allocate("receiver", TyType.fromHintText("String")).getCanonicalIdentity(),
			allocator.allocate("result", TyType.fromHintText("Int")).getCanonicalIdentity()
		];
	}

	static function assertCompilerTemporaryIdentity():Void {
		final first = temporaryIdentities("Main.first#0", "typed-abstract-unary-v1");
		final repeated = temporaryIdentities("Main.first#0", "typed-abstract-unary-v1");
		assertTrue(first[0] == repeated[0] && first[1] == repeated[1], "equivalent lowering produced different temporary identities");
		assertTrue(first[0].indexOf("typed-abstract-unary-v1") >= 0 && first[0].indexOf("Main.first#0") >= 0,
			"compiler temporary identity omitted its function owner or lowering pass");

		final unrelated = new TyCompilerTemporaryAllocator("Main.unrelated#0", "typed-abstract-unary-v1", "__fixture_");
		for (_ in 0...5)
			unrelated.allocate("noise", TyType.fromHintText("Dynamic"));
		final afterUnrelated = temporaryIdentities("Main.first#0", "typed-abstract-unary-v1");
		assertTrue(first[0] == afterUnrelated[0] && first[1] == afterUnrelated[1],
			"allocating temporaries in an unrelated function renumbered the target function");

		final otherOwner = temporaryIdentities("Main.second#0", "typed-abstract-unary-v1");
		assertTrue(first[0] != otherOwner[0], "different function owners received the same compiler temporary identity");
		final otherPass = temporaryIdentities("Main.first#0", "typed-abstract-binary-v1");
		assertTrue(first[0] != otherPass[0], "different lowering passes received the same compiler temporary identity");
	}

	/**
		An incompatible assignment may be tolerated by the permissive bring-up
		typer, but it must not erase the local's already-selected semantic type.
	**/
	static function assertIncompatibleAssignmentKeepsLocalContract():Void {
		final position = new HxPos(0, 1, 1);
		final sourceFunction = new HxFunctionDecl("check", Public, true, [], "Void", [
			SVar("value", "Int", null, position),
			SExpr(EBinop("=", EIdent("value"), EString("not-an-int")), position),
			SVar("dynamicInitializer", "Int", EUntyped(EInt(1)), position),
			SVar("dynamicAssignment", "Int", null, position),
			SExpr(EBinop("=", EIdent("dynamicAssignment"), EUntyped(EInt(2))), position),
			SVar("dynamicCompound", "Int", EInt(3), position),
			SExpr(EBinop("+=", EIdent("dynamicCompound"), EUntyped(EInt(4))), position),
			SVar("inferredDynamic", "", EUntyped(EInt(5)), position)
		], "", [], position);
		final sourceClass = new HxClassDecl("AssignmentContract", true, [sourceFunction], []);
		final parsed = new ParsedModule("", new HxModuleDecl("", [], sourceClass, [sourceClass], false, false), "AssignmentContract.hx");
		final typed = TyperStage.typeModule(parsed).getTypedClasses()[0].getFunctions()[0];
		final statements = typed.getBody().getStatements();
		assertTrue(bindingOfStatement(statements[0]).getType().getSemanticKey() == "primitive:Int",
			"permissive assignment widened an already-known local type instead of preserving its contract");
		assertTrue(bindingOfStatement(statements[2]).getType().getSemanticKey() == "primitive:Int", "Dynamic initializer erased an explicit local type");
		assertTrue(bindingOfStatement(statements[3]).getType().getSemanticKey() == "primitive:Int", "Dynamic assignment erased an explicit local type");
		assertTrue(bindingOfStatement(statements[5]).getType().getSemanticKey() == "primitive:Int",
			"Dynamic compound assignment erased an explicit local type");
		assertTrue(bindingOfStatement(statements[7]).getType().isDynamic(), "an unknown local should still infer Dynamic from a Dynamic initializer");
	}

	static function main():Void {
		assertCompilerTemporaryIdentity();
		assertIncompatibleAssignmentKeepsLocalContract();
		final typed = typedFunction();
		final statements = typed.getBody().getStatements();
		final outer = bindingOfStatement(statements[0]);
		assertTrue(outer.getType().getSemanticKey() == "primitive:Int", "outer local lost its semantic Int type");
		assertTrue(bindingOfRead(statements[1].getExpressions()[0]).getIdentity().equals(outer.getIdentity()),
			"read before the nested block did not select the outer declaration");

		final nestedStatements = statements[2].getStatements();
		final nested = bindingOfStatement(nestedStatements[0]);
		assertTrue(!nested.getIdentity().equals(outer.getIdentity()), "shadowed locals received the same identity");
		assertTrue(nested.getType().getSemanticKey() == "primitive:String", "nested local lost its semantic String type");
		assertTrue(bindingOfRead(nestedStatements[0].getExpressions()[0].getExpressions()[0]).getIdentity().equals(outer.getIdentity()),
			"shadowing declaration became visible inside its own initializer");
		assertTrue(bindingOfRead(nestedStatements[1].getExpressions()[0]).getIdentity().equals(nested.getIdentity()),
			"nested read did not select the nearest declaration");
		final nestedAssignment = nestedStatements[2].getExpressions()[0];
		assertTrue(bindingOfRead(nestedAssignment.getExpressions()[0]).getIdentity().equals(nested.getIdentity()),
			"nested write did not retain the selected declaration");

		assertTrue(bindingOfRead(statements[3].getExpressions()[0]).getIdentity().equals(outer.getIdentity()),
			"outer declaration did not become visible again after the nested block");
		final compound = statements[4].getExpressions()[0];
		assertTrue(bindingOfRead(compound.getExpressions()[0]).getIdentity().equals(outer.getIdentity()),
			"compound assignment lost the selected outer declaration");
		final postfix = statements[5].getExpressions()[0];
		assertTrue(bindingOfRead(postfix.getExpressions()[0]).getIdentity().equals(outer.getIdentity()), "postfix update lost the selected outer declaration");

		final shadowingLambda = statements[6].getExpressions()[0];
		final lambdaBindings = shadowingLambda.getLocalBindings();
		assertTrue(lambdaBindings.length == 1 && !lambdaBindings[0].getIdentity().equals(outer.getIdentity()),
			"lambda parameter did not receive its own identity");
		assertTrue(bindingOfRead(shadowingLambda.getExpressions()[0]).getIdentity().equals(lambdaBindings[0].getIdentity()),
			"lambda body did not select its shadowing parameter");
		final capturingLambda = statements[7].getExpressions()[0];
		assertTrue(bindingOfRead(capturingLambda.getExpressions()[0]).getIdentity().equals(outer.getIdentity()),
			"lambda capture did not retain the outer declaration identity");

		final loop = statements[8];
		final loopBinding = loop.getLocalBindings()[0];
		final loopCopy = loop.getStatements()[0].getStatements()[0];
		assertTrue(bindingOfRead(loopCopy.getExpressions()[0]).getIdentity().equals(loopBinding.getIdentity()),
			"for-loop body did not retain the loop declaration identity");

		final typedTry = statements[9];
		final catchBinding = typedTry.getLocalBindings()[0];
		assertTrue(catchBinding.getType().getSemanticKey() == "primitive:String", "catch binding lost the explicit semantic type selected by shared typing");
		final caught = typedTry.getStatements()[1].getStatements()[0];
		assertTrue(bindingOfRead(caught.getExpressions()[0]).getIdentity().equals(catchBinding.getIdentity()),
			"catch body did not retain the catch declaration identity");

		final expressionDeclaration = statements[10].getExpressions()[0].getExpressions()[0];
		final expressionBinding = expressionDeclaration.getLocalBindings()[0];
		assertTrue(bindingOfRead(statements[11].getExpressions()[0]).getIdentity().equals(expressionBinding.getIdentity()),
			"expression-level variable did not remain bound in its surrounding scope");

		final comprehension = statements[12].getExpressions()[0];
		final comprehensionBinding = comprehension.getLocalBindings()[0];
		final comprehensionValue = comprehension.getExpressions()[comprehension.getExpressions().length - 1];
		assertTrue(bindingOfRead(comprehensionValue).getIdentity().equals(comprehensionBinding.getIdentity()),
			"array-comprehension value did not retain the comprehension declaration identity");
		final prefix = statements[13].getExpressions()[0];
		assertTrue(bindingOfRead(prefix.getExpressions()[0]).getIdentity().equals(outer.getIdentity()), "prefix update lost the selected outer declaration");

		final typedSwitch = statements[14];
		final patternBinding = typedSwitch.getLocalBindings()[0];
		final patternCopy = typedSwitch.getStatements()[0].getStatements()[0];
		assertTrue(bindingOfRead(patternCopy.getExpressions()[0]).getIdentity().equals(patternBinding.getIdentity()),
			"switch body did not retain the selected pattern declaration identity");

		final typedOrStatement = statements[15];
		final orStatementBindings = typedOrStatement.getLocalBindings();
		assertTrue(orStatementBindings.length == 2, "OR-pattern statement did not retain both binding occurrences");
		assertTrue(orStatementBindings[0].getIdentity().equals(orStatementBindings[1].getIdentity()),
			"OR-pattern statement alternatives received different local identities");
		final orCopy = typedOrStatement.getStatements()[0].getStatements()[0];
		assertTrue(bindingOfRead(orCopy.getExpressions()[0]).getIdentity().equals(orStatementBindings[0].getIdentity()),
			"OR-pattern statement body did not read the shared alternative identity");

		final typedOrExpression = statements[16].getExpressions()[0];
		final orExpressionBindings = typedOrExpression.getLocalBindings();
		assertTrue(orExpressionBindings.length == 2, "OR-pattern expression did not retain both binding occurrences");
		assertTrue(orExpressionBindings[0].getIdentity().equals(orExpressionBindings[1].getIdentity()),
			"OR-pattern expression alternatives received different local identities");
		assertTrue(bindingOfRead(typedOrExpression.getExpressions()[1]).getIdentity().equals(orExpressionBindings[0].getIdentity()),
			"OR-pattern expression branch did not read the shared alternative identity");

		final projection = TypedBodySource.functionProjection(typed);
		final projectedKinds = [
			for (entry in projection.getLocalCatalog().getEntries())
				Std.string(entry.getBinding().getKind())
		];
		for (expected in [
			"Variable",
			"LambdaParameter",
			"LoopVariable",
			"CatchVariable",
			"ComprehensionVariable",
			"PatternVariable"
		])
			assertTrue(projectedKinds.indexOf(expected) >= 0, "backend local projection omitted " + expected);
		final projectedStatements = HxFunctionDecl.getBody(projection.getDeclaration());
		switch (projectedStatements[14]) {
			case SSwitch(_, [PBind(projectedPattern)], [SBlock([SVar(_, _, EIdent(projectedRead), _, _)], _)], _):
				assertTrue(projectedPattern == projectedRead, "projected switch body did not use its exact pattern transport name");
				final projectedBinding = projection.getLocalCatalog().findByProjectedName(projectedPattern);
				assertTrue(projectedBinding != null && projectedBinding.getBinding().getIdentity().equals(patternBinding.getIdentity()),
					"projected switch transport name did not resolve to the typed pattern binding");
			case _:
				throw "backend local projection lost the structured switch pattern fixture";
		}
		switch (projectedStatements[15]) {
			case SSwitch(_, [
				POr([
					PArray([PBind(firstProjected), PInt(1)]),
					PArray([PInt(1), PBind(secondProjected)])
				])
			], [SBlock([SVar(_, _, EIdent(projectedRead), _, _)], _)], _):
				assertTrue(firstProjected == secondProjected && firstProjected == projectedRead,
					"projected OR-pattern statement did not reuse one transport name");
				final projectedBinding = projection.getLocalCatalog().findByProjectedName(firstProjected);
				assertTrue(projectedBinding != null
					&& projectedBinding.getBinding().getIdentity().equals(orStatementBindings[0].getIdentity()),
					"projected OR-pattern transport name did not resolve to the shared typed identity");
			case _:
				throw "backend local projection lost the structured OR-pattern statement fixture";
		}

		final repeated = typedFunction();
		assertTrue(bindingOfStatement(repeated.getBody().getStatements()[0]).getIdentity().equals(outer.getIdentity()),
			"equivalent typing produced a different local identity");
		final repeatedOrBindings = repeated.getBody().getStatements()[15].getLocalBindings();
		assertTrue(repeatedOrBindings.length == 2
			&& repeatedOrBindings[0].getIdentity().equals(orStatementBindings[0].getIdentity())
			&& repeatedOrBindings[1].getIdentity().equals(orStatementBindings[0].getIdentity()),
			"equivalent typing produced different shared OR-pattern identities");

		function assertInvalidPattern(pattern:HxSwitchPattern, expected:String):Void {
			final environment = new TyFunctionEnv("invalidPattern", [], [], TyType.fromHintText("Void"), TyType.fromHintText("Void"),
				"LocalIdentity.invalidPattern#0");
			var actual = "";
			try {
				TySwitchPatternBindings.declare(environment, pattern, TyType.fromHintText("Dynamic"));
			} catch (error:Dynamic) {
				actual = Std.string(error);
			}
			assertTrue(actual == expected, "unexpected OR-pattern validation result: " + actual);
			assertTrue(environment.getLocals().length == 0, "invalid OR-pattern partially mutated the function-local catalog");
		}
		assertInvalidPattern(POr([PArray([PBind("left")]), PArray([PBind("right")])]), "Variable right must appear exactly once in each sub-pattern");
		assertInvalidPattern(POr([PArray([PBind("duplicate"), PBind("duplicate")]), PArray([PBind("duplicate")])]),
			"Variable duplicate is bound multiple times");
		TypedBodyInvariant.assertFunction(typed);
	}
}
