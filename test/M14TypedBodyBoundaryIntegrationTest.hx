import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;
import TypedStmt.TypedStmtTag;

/** Focused contract test for the shared structural typed-body boundary. **/
class M14TypedBodyBoundaryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function findClass(module:TypedModule, name:String):TypedClass {
		for (typedClass in module.getTypedClasses())
			if (HxClassDecl.getName(typedClass.getSourceDeclaration()) == name)
				return typedClass;
		throw "missing typed class " + name;
	}

	static function findFunction(typedClass:TypedClass, name:String):TypedFunction {
		for (typedFunction in typedClass.getFunctions())
			if (HxFunctionDecl.getName(typedFunction.getSourceDeclaration()) == name)
				return typedFunction;
		throw "missing typed function " + name;
	}

	static function expectResultCall(body:TypedFunctionBody):TypedExpr {
		for (statement in body.getStatements()) {
			if (statement.getTag() == TypedStmtTag.Var) {
				final names = statement.getNames();
				final expressions = statement.getExpressions();
				if (names[0] == "result") {
					assertTrue(expressions.length == 1, "result initializer was lost");
					return expressions[0];
				}
			}
		}
		throw "missing result initializer";
	}

	static function expectCompoundAssignment(body:TypedFunctionBody):Void {
		for (statement in body.getStatements()) {
			if (statement.getTag() == TypedStmtTag.Expression) {
				final expression = statement.getExpressions()[0];
				if (expression.getTag() == TypedExprTag.CompoundAssign && expression.getTexts()[0] == "+=") {
					final children = expression.getExpressions();
					final target = children[0];
					final value = children[1];
					assertTrue(target.getTag() == TypedExprTag.LocalRead && target.getTexts()[0] == "value",
						"compound assignment target was not a typed local read");
					assertTrue(value.getType().getSemanticKey() == "primitive:Int", "compound assignment value lost its Int type");
					return;
				}
			}
		}
		throw "source-written compound assignment was not represented explicitly";
	}

	static function variableInitializer(body:TypedFunctionBody, name:String):TypedExpr {
		for (statement in body.getStatements()) {
			if (statement.getTag() != TypedStmtTag.Var || statement.getNames()[0] != name)
				continue;
			final expressions = statement.getExpressions();
			if (expressions.length == 1)
				return expressions[0];
		}
		throw "missing initializer for " + name;
	}

	static function containsCallNamed(expression:TypedExpr, name:String):Bool {
		if (expression.getTag() == TypedExprTag.Call) {
			final children = expression.getExpressions();
			if (children.length > 0 && children[0].getTag() == TypedExprTag.NameRead && children[0].getTexts()[0] == name)
				return true;
		}
		for (child in expression.getExpressions())
			if (containsCallNamed(child, name))
				return true;
		return false;
	}

	static function containsTag(expression:TypedExpr, tag:TypedExprTag):Bool {
		if (expression.getTag() == tag)
			return true;
		for (child in expression.getExpressions())
			if (containsTag(child, tag))
				return true;
		return false;
	}

	static function bodyContainsTag(body:TypedFunctionBody, tag:TypedExprTag):Bool {
		function statementContains(statement:TypedStmt):Bool {
			for (expression in statement.getExpressions())
				if (containsTag(expression, tag))
					return true;
			for (child in statement.getStatements())
				if (statementContains(child))
					return true;
			return false;
		}
		for (statement in body.getStatements())
			if (statementContains(statement))
				return true;
		return false;
	}

	static function assertLifecycleGuard(typed:TypedModule, main:TypedFunction):Void {
		final program = MacroStage.expandProgram([typed], []);
		HxFunctionDecl.getBody(main.getSourceDeclaration()).push(SExpr(EInt(0), new HxPos(0, 99, 1)));
		var failure:Null<String> = null;
		try {
			backend.GenIrBoundary.requireProgram(program);
		} catch (error:String) {
			failure = error;
		}
		assertTrue(failure != null && failure.indexOf("typed body revision mismatch") >= 0,
			"parsed-body mutation after typed-program creation did not invalidate the sealed backend revision");
	}

	static function assertOpaqueGuard():Void {
		final position = new HxPos(0, 1, 1);
		final sourceFunction = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [SExpr(EUnsupported("value++"), position)], "", [], position);
		final sourceClass = new HxClassDecl("Opaque", true, [sourceFunction], []);
		final parsed = new ParsedModule("", new HxModuleDecl("", [], sourceClass, [sourceClass], false, false), "Opaque.hx");
		var failure:Null<String> = null;
		try {
			new TypedModule(parsed, new TyModuleEnv("", [], new TyClassEnv("Opaque", [])));
		} catch (error:String) {
			failure = error;
		}
		assertTrue(failure != null && failure.indexOf("can hide operator or mutation semantics") >= 0,
			"opaque typed-body leaf accepted hidden increment syntax");
	}

	static function assertReturnMacroArgumentStructure():Void {
		final filePath = "checks/ReturnMacroArgument.hx";
		final source = [
			"class ReturnMacroArgument {",
			"  function get_str():String {",
			"    shouldFail(return (null : Null<String>));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("ReturnMacroArgument", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final body = findFunction(findClass(typed, "ReturnMacroArgument"), "get_str").getBody();
		final statement = body.getStatements()[0];
		assertTrue(statement.getTag() == TypedStmtTag.Expression, "macro call should remain an expression before macro expansion");
		final call = statement.getExpressions()[0];
		assertTrue(call.getTag() == TypedExprTag.Call, "shouldFail call was not kept as a structural typed call");
		final returnExpression = call.getExpressions()[1];
		assertTrue(returnExpression.getTag() == TypedExprTag.ReturnExpr, "return macro argument lost its typed return node");
		final typedCast = returnExpression.getExpressions()[0];
		assertTrue(typedCast.getTag() == TypedExprTag.Cast && typedCast.getType().getDisplay() == "Null<String>",
			"return macro argument lost its Null<String> cast");
		assertTrue(typedCast.getExpressions()[0].getTag() == TypedExprTag.NullValue, "typed return cast lost its null child");
		TypedBodyInvariant.assertClasses(typed.getTypedClasses());
	}

	static function assertVariableDeclarationMacroArgumentStructure():Void {
		final filePath = "checks/VariableDeclarationMacroArgument.hx";
		final source = [
			"class VariableDeclarationMacroArgument {",
			"  function check(nullable:Null<String>):Void {",
			"    shouldFail(var value:String = nullable);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("VariableDeclarationMacroArgument", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final body = findFunction(findClass(typed, "VariableDeclarationMacroArgument"), "check").getBody();
		final call = body.getStatements()[0].getExpressions()[0];
		assertTrue(call.getTag() == TypedExprTag.Call, "shouldFail declaration call was not kept as a structural typed call");
		final declarationList = call.getExpressions()[1];
		assertTrue(declarationList.getTag() == TypedExprTag.VariableDeclarations, "variable declaration macro argument lost its typed declaration list");
		final declaration = declarationList.getExpressions()[0];
		assertTrue(declaration.getTag() == TypedExprTag.VariableDeclaration, "typed declaration list lost its declaration child");
		assertTrue(declaration.getTexts()[0] == "value"
			&& declaration.getTexts()[1] == "String", "typed variable declaration lost its name or written type");
		assertTrue(declaration.getType().getDisplay() == "String", "typed variable declaration lost its declared semantic type");
		assertTrue(declaration.getPosition() != null
			&& declaration.getPosition().getLine() == 3, "typed variable declaration lost its exact source line");
		assertTrue(declaration.getExpressions()[0].getTag() == TypedExprTag.LocalRead, "typed variable declaration lost its recursive initializer child");
		switch (TypedBodySource.expression(declarationList)) {
			case EVars([EVariableDeclaration(name, typeHint, _, _, _, _)]):
				assertTrue(name == "value" && typeHint == "String", "typed-body source projection changed the variable declaration");
			case _:
				throw "typed-body source projection lost the expression-level declaration list";
		}
		TypedBodyInvariant.assertClasses(typed.getTypedClasses());
	}

	static function assertLocalVariableMetadataStructure():Void {
		final filePath = "checks/LocalVariableMetadata.hx";
		final source = [
			"class LocalVariableMetadata {",
			"  function check():Void {",
			"    var @:nullSafety(Off) nullable:Null<String> = null;",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("LocalVariableMetadata", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final body = findFunction(findClass(typed, "LocalVariableMetadata"), "check").getBody();
		final statement = body.getStatements()[0];
		assertTrue(statement.getTag() == TypedStmtTag.Var, "annotated local did not become a typed variable statement");
		assertTrue(statement.getMetadata().join("|") == "@:nullSafety(Off)", "typed local lost its null-safety metadata");
		switch (TypedBodySource.statement(statement)) {
			case SVar("nullable", "Null<String>", ENull, position, metadata):
				assertTrue(position.getLine() == 3, "annotated local lost its exact source line");
				assertTrue(metadata != null
					&& metadata.join("|") == "@:nullSafety(Off)", "typed-body source projection dropped local metadata");
			case _:
				throw "typed-body source projection changed the annotated local declaration";
		}
		final position = new HxPos(0, 1, 1);
		final annotatedFingerprint = TypedBodyFingerprint.forStatements([SVar("value", "Int", EInt(1), position, ["@:example"])]);
		final plainFingerprint = TypedBodyFingerprint.forStatements([SVar("value", "Int", EInt(1), position, [])]);
		assertTrue(annotatedFingerprint != plainFingerprint, "body fingerprint ignored local-variable metadata");
		TypedBodyInvariant.assertClasses(typed.getTypedClasses());
	}

	static function assertWhileMacroArgumentStructure():Void {
		final filePath = "checks/WhileMacroArgument.hx";
		final source = [
			"class WhileMacroArgument {",
			"  static function shouldFail(value:Dynamic):Void {}",
			"  static function tick(value:Bool):Void {}",
			"  static function check(a:Bool):Void {",
			"    shouldFail(while (a) { tick(a); });",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("WhileMacroArgument", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final body = findFunction(findClass(typed, "WhileMacroArgument"), "check").getBody();
		final call = body.getStatements()[0].getExpressions()[0];
		assertTrue(call.getTag() == TypedExprTag.Call, "while macro fixture lost its outer call");
		final loop = call.getExpressions()[1];
		assertTrue(loop.getTag() == TypedExprTag.WhileExpr, "while macro argument did not become a typed loop expression");
		assertTrue(loop.getBoolValue(), "while macro block lost its brace-block identity");
		assertTrue(loop.getExpressions().length == 2, "typed while macro argument lost its condition or body expression");
		assertTrue(loop.getExpressions()[0].getTag() == TypedExprTag.LocalRead && loop.getExpressions()[0].getTexts()[0] == "a",
			"typed while macro condition was not resolved as the function parameter");
		assertTrue(loop.getPosition() != null && loop.getPosition().getLine() == 5, "typed while macro argument lost the loop's exact source line");
		switch (TypedBodySource.statements(body)[0]) {
			case SExpr(ECall(EIdent("shouldFail"), [EWhile(EIdent("a"), [ECall(EIdent("tick"), [EIdent("a")])], true, position)]), _):
				assertTrue(position.getLine() == 5, "typed-body source projection changed the while position");
			case _:
				throw "typed-body source projection changed the while macro argument";
		}
		final position = new HxPos(0, 1, 1);
		final emptyFingerprint = TypedBodyFingerprint.forStatements([SExpr(EWhile(EIdent("a"), [], true, position), position)]);
		final bodyFingerprint = TypedBodyFingerprint.forStatements([
			SExpr(EWhile(EIdent("a"), [ECall(EIdent("tick"), [])], true, position), position)
		]);
		assertTrue(emptyFingerprint != bodyFingerprint, "body fingerprint ignored the while macro body");
		TypedBodyInvariant.assertClasses(typed.getTypedClasses());
	}

	static function assertNullCoalescingLoopControlStructure():Void {
		final filePath = "checks/NullCoalescingLoopControl.hx";
		final source = [
			"class NullCoalescingLoopControl {",
			"  static var fallback:Null<String>;",
			"  static function check():Void {",
			"    for (i in 0...1) {",
			"      var value:String = fallback ?? continue;",
			"      var other:String = fallback ?? break;",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("NullCoalescingLoopControl", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final body = findFunction(findClass(typed, "NullCoalescingLoopControl"), "check").getBody();
		final loop = body.getStatements()[0];
		assertTrue(loop.getTag() == TypedStmtTag.ForIn, "loop-control fixture lost its for loop");
		final block = loop.getStatements()[0];
		assertTrue(block.getTag() == TypedStmtTag.Block
			&& block.getStatements().length == 2, "loop-control fixture lost its local declarations");
		final continueInitializer = block.getStatements()[0].getExpressions()[0];
		final breakInitializer = block.getStatements()[1].getExpressions()[0];
		assertTrue(continueInitializer.getTag() == TypedExprTag.Binary && continueInitializer.getTexts()[0] == "??",
			"continue fixture lost its null-coalescing expression");
		assertTrue(breakInitializer.getTag() == TypedExprTag.Binary && breakInitializer.getTexts()[0] == "??",
			"break fixture lost its null-coalescing expression");
		final typedContinue = continueInitializer.getExpressions()[1];
		final typedBreak = breakInitializer.getExpressions()[1];
		assertTrue(typedContinue.getTag() == TypedExprTag.ContinueExpr && typedContinue.getType().isNoNormalCompletion(),
			"typed continue was given a fake runtime value");
		assertTrue(typedBreak.getTag() == TypedExprTag.BreakExpr
			&& typedBreak.getType().isNoNormalCompletion(), "typed break was given a fake runtime value");
		assertTrue(continueInitializer.getType().getSemanticKey() == "primitive:String"
			&& breakInitializer.getType().getSemanticKey() == "primitive:String",
			"loop control changed the value type of the non-null branch");
		switch (TypedBodySource.statements(body)[0]) {
			case SForIn(_, _, SBlock([
				SVar("value", "String", EBinop("??", _, EContinue(continuePosition)), _, _),
				SVar("other", "String", EBinop("??", _, EBreak(breakPosition)), _, _)
			], _), _):
				assertTrue(continuePosition.getLine() == 5 && breakPosition.getLine() == 6, "typed-body source projection changed loop-control positions");
			case _:
				throw "typed-body source projection changed null-coalescing loop control";
		}
		final position = new HxPos(0, 1, 1);
		final continueFingerprint = TypedBodyFingerprint.forStatements([SExpr(EContinue(position), position)]);
		final breakFingerprint = TypedBodyFingerprint.forStatements([SExpr(EBreak(position), position)]);
		assertTrue(continueFingerprint != breakFingerprint, "body fingerprint confused continue with break");
		assertTrue(TyType.unify(TyType.noNormalCompletion(), TyType.fromHintText("String")).getSemanticKey() == "primitive:String",
			"no-normal-completion did not preserve the normally completing branch type");
		TypedBodyInvariant.assertClasses(typed.getTypedClasses());
	}

	static function assertLoweringNodeSet():Void {
		final position = new HxPos(0, 1, 1);
		final intType = TyType.fromHintText("Int");
		final sourceFunction = new HxFunctionDecl("lowered", HxVisibility.Private, false, [], "Int", [], "", [], position);
		final owner = TypedFunction.stableIdentityFor("Main", 0, sourceFunction, null);
		final allocator = new TyCompilerTemporaryAllocator(owner, "typed-body-boundary-fixture-v1", "__fixture_");
		final valueBinding = allocator.allocate("value", intType);
		final operandBinding = allocator.allocate("op", intType);
		final value = TypedExpr.temporary(valueBinding.getSourceName(), "Int", TypedExpr.intLiteral(0, intType, null), TyType.fromHintText("Void"), null,
			valueBinding);
		final operand = TypedExpr.temporary(operandBinding.getSourceName(), "Int", TypedExpr.intLiteral(1, intType, null), TyType.fromHintText("Void"), null,
			operandBinding);
		final assignment = TypedExpr.assign(TypedExpr.localRead(valueBinding.getSourceName(), intType, null, valueBinding),
			TypedExpr.localRead(operandBinding.getSourceName(), intType, null, operandBinding), intType, null);
		final block = TypedExpr.block([value, operand, assignment], intType, position);
		final typedFunction = new TypedFunction("Main", 0, sourceFunction, null, null,
			new TypedFunctionBody([TypedStmt.expressionStmt(block, position)], TypedBodyFingerprint.forStatements([])));
		TypedBodyInvariant.assertFunction(typedFunction);

		var missingBindingRejected = false;
		try {
			final invalid = new TypedFunction("Main", 0, sourceFunction, null, null, new TypedFunctionBody([
				TypedStmt.expressionStmt(TypedExpr.temporary("__missing", "Int", TypedExpr.intLiteral(1, intType, null), TyType.fromHintText("Void"), null),
					position)
			], TypedBodyFingerprint.forStatements([])));
			TypedBodyInvariant.assertFunction(invalid);
		} catch (_:Dynamic) {
			missingBindingRejected = true;
		}
		assertTrue(missingBindingRejected, "typed-body invariant accepted a compiler temporary without a declaration binding");

		var missingReadBindingRejected = false;
		try {
			final invalidRead = TypedExpr.assign(TypedExpr.localRead(valueBinding.getSourceName(), intType, null, valueBinding),
				TypedExpr.localRead(valueBinding.getSourceName(), intType, null), intType, null);
			final invalid = new TypedFunction("Main", 0, sourceFunction, null, null, new TypedFunctionBody([
				TypedStmt.expressionStmt(TypedExpr.block([value, invalidRead], intType, position), position)
			], TypedBodyFingerprint.forStatements([])));
			TypedBodyInvariant.assertFunction(invalid);
		} catch (_:Dynamic) {
			missingReadBindingRejected = true;
		}
		assertTrue(missingReadBindingRejected, "typed-body invariant accepted a structural local read without a declaration binding");
	}

	static function assertNullableSourceProjection():Void {
		final intType = TyType.fromHintText("Int");
		final boolType = TyType.fromHintText("Bool");
		final arrayType = TyType.fromHintText("Array<Int>");
		final iterable = TypedExpr.range(TypedExpr.intLiteral(0, intType, null), TypedExpr.intLiteral(3, intType, null), arrayType, null);
		final value = TypedExpr.localRead("entry", intType, null);
		final guarded = TypedExpr.arrayComprehension("entry", iterable, TypedExpr.boolLiteral(true, boolType, null), value, arrayType, null);
		final unguarded = TypedExpr.arrayComprehension("entry", iterable, null, value, arrayType, null);
		assertTrue(switch (TypedBodySource.expression(guarded)) {
			case EArrayComprehension("entry", ERange(EInt(0), EInt(3)), EBool(true), EIdent("entry")): true;
			case _: false;
		}, "guarded typed array comprehension lost its optional source expression");
		assertTrue(switch (TypedBodySource.expression(unguarded)) {
			case EArrayComprehension("entry", ERange(EInt(0), EInt(3)), null, EIdent("entry")): true;
			case _: false;
		}, "unguarded typed array comprehension fabricated an optional source expression");

		final position = new HxPos(0, 1, 1);
		assertTrue(switch (TypedBodySource.statement(TypedStmt.variable("present", "Int", TypedExpr.intLiteral(1, intType, null), position))) {
			case SVar("present", "Int", EInt(1), _): true;
			case _: false;
		}, "typed variable projection lost its initializer");
		assertTrue(switch (TypedBodySource.statement(TypedStmt.variable("missing", "Int", null, position))) {
			case SVar("missing", "Int", null, _): true;
			case _: false;
		}, "typed variable projection fabricated a missing initializer");
	}

	/** Keep source-inferred constructors distinct from explicit local annotations. **/
	static function assertInferredConstructorSourceProjection():Void {
		final position = new HxPos(0, 1, 1);
		final identity = new TyNominalTypeId("haxe.ds.IntMap");
		final declarations = [
			TypedStmt.variable("h", "IntMap<Int>",
				TypedExpr.newValue("IntMap<Int>", [], TyType.nominal(identity, [TyType.fromHintText("Int")], "IntMap<Int>"), position), position),
			TypedStmt.variable("h", "", TypedExpr.newValue("IntMap", [], TyType.nominal(identity, [], "IntMap"), position), position),
		];
		assertTrue(declarations.length == 2, "same-named constructor locals did not remain separate typed statements");
		assertTrue(declarations[0].getNames()[1] == "IntMap<Int>", "explicit constructor local lost its source annotation");
		assertTrue(declarations[1].getNames()[1] == "", "inferred constructor local gained an annotation before source projection");
		final inferred = declarations[1].getExpressions()[0];
		assertTrue(inferred.getTag() == TypedExprTag.NewValue && inferred.getType().getNominalIdentity() != null,
			"inferred constructor lost its nominal semantic type");
		assertTrue(switch (TypedBodySource.statement(declarations[0])) {
			case SVar("h", "IntMap<Int>", ENew("IntMap<Int>", []), _): true;
			case _: false;
		}, "explicit constructor annotation did not survive typed-body projection");
		assertTrue(switch (TypedBodySource.statement(declarations[1])) {
			case SVar("h", "", ENew("IntMap", []), _): true;
			case _: false;
		}, "source inference became a false bare constructor annotation");
	}

	static function assertStructuralExpressionBlock():Void {
		final parsed = ParserStage.parse([
			"class Main {",
			"  static function main() {",
			"    var prefix = \"value\";",
			"    var result = { var text:String = prefix + \":ok\"; text; };",
			"  }",
			"}",
		].join("\n"), "TypedBlock.hx");
		final typed = TyperStage.typeModule(parsed);
		final main = findFunction(findClass(typed, "Main"), "main");
		var block:Null<TypedExpr> = null;
		for (statement in main.getBody().getStatements()) {
			if (statement.getTag() != TypedStmtTag.Var || statement.getNames()[0] != "result")
				continue;
			block = statement.getExpressions()[0];
		}
		assertTrue(block != null && block.getTag() == TypedExprTag.Block, "typed expression block remained an opaque source payload");
		final children = block.getExpressions();
		assertTrue(children.length == 2
			&& children[0].getTag() == TypedExprTag.Temporary, "typed expression block did not expose its temporary declaration");
		assertTrue(children[0].getTexts()[0] == "text" && children[0].getTexts()[1] == "String", "typed temporary lost its name or declared type");
		final initializer = children[0].getExpressions()[0];
		assertTrue(initializer.getTag() == TypedExprTag.Binary && initializer.getTexts()[0] == "+",
			"operator inside expression block was not structurally typed");
		assertTrue(children[1].getTag() == TypedExprTag.LocalRead && children[1].getType().getSemanticKey() == "primitive:String",
			"expression-block result did not resolve through its lexical temporary");
		final projected = TypedBodySource.expression(block);
		assertTrue(switch (projected) {
			case ECall(ECast(ELambda(["text"], EIdent("text")), "(String)->Dynamic"), [EBinop("+", EIdent("prefix"), EString(":ok"))]): true;
			case _: false;
		}, "typed expression block projection did not preserve its structural binding");
	}

	static function assertStructuralDoWhileExpression():Void {
		final parsed = ParserStage.parse([
			"class Main {",
			"  static function main() {",
			"    var value = 0;",
			"    var run = function() return (do { value += 1; } while (value < 2));",
			"  }",
			"}",
		].join("\n"), "TypedDoWhile.hx");
		final typed = TyperStage.typeModule(parsed);
		final run = variableInitializer(findFunction(findClass(typed, "Main"), "main").getBody(), "run");
		assertTrue(containsCallNamed(run, "__hxhx_do_while"), "expression-position do/while did not become a structural shared call");
		assertTrue(containsTag(run, TypedExprTag.CompoundAssign), "do/while body hid its compound assignment from typed traversal");
		assertTrue(!containsTag(run, TypedExprTag.Opaque), "expression-position do/while retained an opaque source payload");
	}

	/** Keep `?.` distinct from an unconditional field read throughout body sealing. **/
	static function assertNullSafeCallStructure():Void {
		final parsed = ParserStage.parse([
			"class FlashLike {",
			"  static function readUntil(expected:String, ?unexpectedStrings:Map<String, ()->Void>) {",
			"    final possibleStrings = unexpectedStrings?.copy() ?? [];",
			"    possibleStrings[expected] = function() {};",
			"  }",
			"}",
		].join("\n"), "FlashLike.hx");
		final readUntil = findFunction(findClass(TyperStage.typeModule(parsed), "FlashLike"), "readUntil");
		final initializer = variableInitializer(readUntil.getBody(), "possibleStrings");
		assertTrue(initializer.getTag() == TypedExprTag.Binary && initializer.getTexts()[0] == "??",
			"null-safe copy fallback was not retained as a typed null-coalescing expression");
		final copyCall = initializer.getExpressions()[0];
		assertTrue(copyCall.getTag() == TypedExprTag.Call, "null-safe copy invocation was not retained as a typed call");
		assertTrue(copyCall.getType().isNullable(), "null-safe copy invocation did not retain a nullable result type");
		final callee = copyCall.getExpressions()[0];
		assertTrue(callee.getTag() == TypedExprTag.NullSafeFieldRead && callee.getTexts()[0] == "copy",
			"null-safe copy invocation became an unconditional field read");
		assertTrue(callee.getExpressions()[0].getTag() == TypedExprTag.LocalRead, "null-safe copy receiver was not retained as a structural typed child");
		assertTrue(!containsTag(initializer, TypedExprTag.Opaque), "null-safe copy invocation remained hidden in an opaque typed leaf");
		TypedBodyInvariant.assertFunction(readUntil);
	}

	static function assertAbstractThisAssignment():Void {
		final parsed = ParserStage.parse([
			"abstract RestLike<T>(Array<T>) {",
			"  inline function new(array:Array<T>):Void",
			"    this = array;",
			"}",
		].join("\n"), "RestLike.hx");
		final typed = TyperStage.typeModule(parsed);
		final constructor = findFunction(findClass(typed, "RestLike"), "new");
		final statements = constructor.getBody().getStatements();
		assertTrue(statements.length == 1 && statements[0].getTag() == TypedStmtTag.Expression,
			"abstract constructor body was not retained as an expression statement");
		final assignment = statements[0].getExpressions()[0];
		assertTrue(assignment.getTag() == TypedExprTag.Assign, "abstract-this assignment remained opaque");
		assertTrue(assignment.getExpressions()[0].getTag() == TypedExprTag.ThisValue, "abstract-this assignment lost its typed target");
	}

	static function assertStructuralTryCatchExpression():Void {
		final parsed = ParserStage.parse([
			"class Main {",
			"  static function main() {",
			"    var value = 1;",
			"    var result = try { value += 1; value; } catch(e:Dynamic) { trace(\"failed:\" + e); 0; };",
			"  }",
			"}",
		].join("\n"), "TypedTry.hx");
		final result = variableInitializer(findFunction(findClass(TyperStage.typeModule(parsed), "Main"), "main").getBody(), "result");
		assertTrue(containsCallNamed(result, "__hxhx_try"), "expression-level try/catch did not become a structural shared call");
		assertTrue(containsTag(result, TypedExprTag.CompoundAssign), "try body hid its mutation from typed traversal");
		assertTrue(containsTag(result, TypedExprTag.Binary), "catch body hid its string concatenation from typed traversal");
		assertTrue(!containsTag(result, TypedExprTag.Opaque), "expression-level try/catch retained an opaque source payload");
		final ocaml = @:privateAccess EmitterStage.exprToOcaml(TypedBodySource.expression(result));
		assertTrue(ocaml.indexOf("HxRuntime.hx_try") >= 0, "OCaml backend did not consume the structural try/catch call");
		assertTrue(ocaml.indexOf("__hxhx_try") < 0, "OCaml backend leaked the shared structural sentinel into generated source");
	}

	static function assertStructuralTerminalReturnBlock():Void {
		final position = new HxPos(0, 1, 1);
		final raw = [
			"opaque_block_expr:{",
			"  if (values.length == 0) throw 'empty';",
			"  var total = 0;",
			"  for (i in 0...values.length) {",
			"    total = total + values[i];",
			"    if (total < 0) return total;",
			"  }",
			"  return total;",
			"}",
		].join("\n");
		final sourceFunction = new HxFunctionDecl("decode", HxVisibility.Public, true, [new HxFunctionArg("values", "Array<Int>", NoDefault)], "Int",
			[SReturn(ETryCatchRaw(raw), position)], "", [], position);
		final sourceClass = new HxClassDecl("Main", true, [sourceFunction], []);
		final parsed = new ParsedModule("", new HxModuleDecl("", [], sourceClass, [sourceClass], false, false), "TypedTerminalReturnBlock.hx");
		final body = findFunction(findClass(TyperStage.typeModule(parsed), "Main"), "decode").getBody();
		assertTrue(body.getStatements().length == 1 && body.getStatements()[0].getTag() == TypedStmtTag.Block,
			"terminal return-block expression did not lift into structural statements");
		assertTrue(bodyContainsTag(body, TypedExprTag.Assign), "terminal return block hid its assignment");
		assertTrue(bodyContainsTag(body, TypedExprTag.ArrayAccess), "terminal return block hid its indexed read");
		assertTrue(!bodyContainsTag(body, TypedExprTag.Opaque), "terminal return block retained an opaque source payload");
	}

	static function assertStructuralUntypedStatementBlock():Void {
		final position = new HxPos(0, 1, 1);
		final raw = [
			"opaque_block_expr:{",
			"  if (kind(values) != arrayKind) throw 'invalid';",
			"  for (i in 0...size(values))",
			"    if (kind(values[i]) != intKind) throw 'invalid';",
			"  var total:Dynamic = 0;",
			"  for (i in 0...size(values)) total = total + values[i];",
			"  return total;",
			"}",
		].join("\n");
		final sourceFunction = new HxFunctionDecl("decodeUntyped", HxVisibility.Public, true, [new HxFunctionArg("values", "Array<Int>", NoDefault)],
			"Dynamic", [SExpr(EUntyped(ETryCatchRaw(raw)), position)], "", [], position);
		final sourceClass = new HxClassDecl("Main", true, [sourceFunction], []);
		final parsed = new ParsedModule("", new HxModuleDecl("", [], sourceClass, [sourceClass], false, false), "TypedUntypedBlock.hx");
		final body = findFunction(findClass(TyperStage.typeModule(parsed), "Main"), "decodeUntyped").getBody();
		assertTrue(body.getStatements().length == 1 && body.getStatements()[0].getTag() == TypedStmtTag.Block,
			"untyped statement block did not lift into structural statements");
		assertTrue(bodyContainsTag(body, TypedExprTag.Assign), "untyped statement block hid its assignment");
		assertTrue(bodyContainsTag(body, TypedExprTag.ArrayAccess), "untyped statement block hid its indexed read");
		assertTrue(bodyContainsTag(body, TypedExprTag.Untyped), "untyped statement block lost its explicit typing escape hatch");
		assertTrue(!bodyContainsTag(body, TypedExprTag.Opaque), "untyped statement block retained an opaque source payload");
		final projected = TypedBodySource.statements(body);
		final projectedStatements = switch (projected[0]) {
			case SBlock(statements, _): statements;
			case _: [];
		};
		var foundUntypedInitializer = false;
		for (statement in projectedStatements)
			switch (statement) {
				case SVar("total", "Dynamic", EUntyped(EInt(0)), _):
					foundUntypedInitializer = true;
				case _:
			}
		assertTrue(foundUntypedInitializer, "nullable untyped variable initializer did not survive typed-body source reconstruction");
	}

	static function assertConditionalElseIfStructure():Void {
		final parsed = ParserStage.parse([
			"class Main {",
			"  static function main() {",
			"    var value = 0;",
			"    if (value == 0) { value = 1; }",
			"    #if target.unicode",
			"    else if (value >= 1) { value += 2; }",
			"    #end",
			"    else if (value > 3) { value--; }",
			"  }",
			"}",
		].join("\n"), "TypedConditionalElse.hx");
		final body = findFunction(findClass(TyperStage.typeModule(parsed), "Main"), "main").getBody();
		assertTrue(bodyContainsTag(body, TypedExprTag.CompoundAssign), "conditional-compilation marker detached a compound-assignment else branch");
		assertTrue(bodyContainsTag(body, TypedExprTag.Unary), "conditional-compilation marker detached a postfix else branch");
		assertTrue(!bodyContainsTag(body, TypedExprTag.Opaque), "conditional else-if chain retained an opaque parser recovery node");
	}

	/** Prove strict body sealing recognizes an exact instance call as a method read, not a missing data field. **/
	static function assertStrictInstanceMethodCallee():Void {
		final filePath = "checks/StrictInstanceCall.hx";
		final parsed = ParserStage.parse([
			"class StrictInstanceCall {",
			"  var value:Int;",
			"  public function new() this.value = 41;",
			"  function ping():Int return this.value;",
			"  static function main() {",
			"    var instance = new StrictInstanceCall();",
			"    instance.ping();",
			"  }",
			"}",
		].join("\n"), filePath);
		final resolved = new ResolvedModule("StrictInstanceCall", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["checks"], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);

		final oldStrict = Sys.getEnv("HXHX_TYPER_STRICT");
		var typed:Null<TypedModule> = null;
		try {
			Sys.putEnv("HXHX_TYPER_STRICT", "1");
			typed = TyperStage.typeResolvedModule(resolved, index, loader);
		} catch (error:Dynamic) {
			if (oldStrict == null)
				Sys.putEnv("HXHX_TYPER_STRICT", "");
			else
				Sys.putEnv("HXHX_TYPER_STRICT", oldStrict);
			throw error;
		}
		if (oldStrict == null)
			Sys.putEnv("HXHX_TYPER_STRICT", "");
		else
			Sys.putEnv("HXHX_TYPER_STRICT", oldStrict);

		final body = findFunction(findClass(typed, "StrictInstanceCall"), "main").getBody();
		final statements = body.getStatements();
		final call = statements[statements.length - 1].getExpressions()[0];
		assertTrue(call.getTag() == TypedExprTag.Call, "strict instance method call was not structurally sealed");
		assertTrue(call.getDeclaration() != null && call.getDeclaration().getSignature().getName() == "ping",
			"strict instance method call lost its exact declaration identity");
		final callee = call.getExpressions()[0];
		assertTrue(callee.getTag() == TypedExprTag.FieldRead && callee.getTexts()[0] == "ping",
			"strict instance method callee was not retained as a structural member read");

		final missingParsed = ParserStage.parse([
			"class StrictMissingMember {",
			"  public function new() {}",
			"  static function main() {",
			"    var instance = new StrictMissingMember();",
			"    var absent = instance.missing;",
			"  }",
			"}",
		].join("\n"), "checks/StrictMissingMember.hx");
		final missingResolved = new ResolvedModule("StrictMissingMember", "checks/StrictMissingMember.hx", missingParsed);
		final missingIndex = TyperIndex.build([missingResolved]);
		final missingLoader = new ModuleLoader(["checks"], new StringMap<String>(), missingIndex, function(_):Bool return false);
		missingLoader.markResolvedAlready([missingResolved]);
		var missingFailure:Null<String> = null;
		try {
			Sys.putEnv("HXHX_TYPER_STRICT", "1");
			TyperStage.typeResolvedModule(missingResolved, missingIndex, missingLoader);
		} catch (error:Dynamic) {
			missingFailure = Std.string(error);
		}
		if (oldStrict == null)
			Sys.putEnv("HXHX_TYPER_STRICT", "");
		else
			Sys.putEnv("HXHX_TYPER_STRICT", oldStrict);
		assertTrue(missingFailure != null && missingFailure.indexOf("Unknown field missing") >= 0,
			"recognizing declared method reads weakened strict missing-field diagnostics");
	}

	/**
		Keep method-only generic parameters inside the selected call until argument
		types bind them. A parameter that remains unbound must not escape as a
		caller-visible nominal type or collide with an unrelated class of the same
		name.
	**/
	static function assertMethodGenericResultSpecialization():Void {
		final filePath = "checks/GenericMethodResults.hx";
		final parsed = ParserStage.parse([
			"class Array<T> {",
			"  public function new() {}",
			"}",
			"class A {}",
			"class GenericResultOwner {",
			"  static function identity<T>(value:T):T return value;",
			"  static function wrap<T>(value:Array<T>):Array<T> return value;",
			"  static function same<T>(left:T, right:T):T return left;",
			"  static function constrained<T:Int>(value:T):T return value;",
			"  static function unbound<A>(value:Dynamic):Array<A> return [];",
			"  static function main() {",
			"    var scalar = identity(7);",
			"    var nested = wrap([\"x\"]);",
			"    var conflict = same(1, \"x\");",
			"    var unsupportedConstraint = constrained(1);",
			"    var unresolved = unbound({});",
			"  }",
			"}",
		].join("\n"), filePath);
		final resolved = new ResolvedModule("GenericMethodResults", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["checks"], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final body = findFunction(findClass(TyperStage.typeResolvedModule(resolved, index, loader), "GenericResultOwner"), "main").getBody();
		final scalar = variableInitializer(body, "scalar");
		assertTrue(scalar.getType().getSemanticKey() == "primitive:Int", "direct method-generic result did not specialize to the argument type");
		assertTrue(scalar.getDeclaration() != null && scalar.getDeclaration().getSignature().getName() == "identity",
			"specializing a direct method-generic result lost the exact declaration");

		final nested = variableInitializer(body, "nested");
		final nestedArguments = nested.getType().getTypeArguments();
		assertTrue(nested.getType().getNominalIdentity() != null
			&& nestedArguments.length == 1
			&& nestedArguments[0].getSemanticKey() == "primitive:String",
			"nested method-generic result did not specialize Array<T> to Array<String>");

		final conflict = variableInitializer(body, "conflict");
		assertTrue(conflict.getType().isUnknown(), "conflicting method-generic arguments produced a false common result");
		assertTrue(conflict.getDeclaration() == null, "conflicting method-generic arguments selected an inapplicable declaration");

		final unsupportedConstraint = variableInitializer(body, "unsupportedConstraint");
		assertTrue(unsupportedConstraint.getType().isUnknown(), "unsupported constrained generic inference produced a false concrete result");
		assertTrue(unsupportedConstraint.getDeclaration() == null,
			"unsupported constrained generic inference selected a declaration without proving its constraint");

		final unresolved = variableInitializer(body, "unresolved");
		assertTrue(unresolved.getType().isUnknown(), "unbound method-generic result escaped as a caller-visible nominal type");
		assertTrue(unresolved.getDeclaration() != null && unresolved.getDeclaration().getSignature().getName() == "unbound",
			"unknown generic result lost the exact selected declaration");
		var keptBlankHint = false;
		for (statement in body.getStatements()) {
			if (statement.getTag() != TypedStmtTag.Var || statement.getNames()[0] != "unresolved")
				continue;
			keptBlankHint = switch (TypedBodySource.statement(statement)) {
				case SVar("unresolved", "", _, _): true;
				case _: false;
			};
		}
		assertTrue(keptBlankHint, "unbound method generic became a false source-level local annotation");
	}

	/** A field's nominal value type must not make its variable name look like a type alias. **/
	static function assertNominalFieldReadRemainsAValue():Void {
		final filePath = "checks/NominalFieldRead.hx";
		final parsed = ParserStage.parse([
			"class TreeNode {}",
			"class NominalFieldRead {",
			"  var root:TreeNode;",
			"  function read():TreeNode return root;",
			"}",
		].join("\n"), filePath);
		final resolved = new ResolvedModule("NominalFieldRead", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["checks"], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final body = findFunction(findClass(typed, "NominalFieldRead"), "read").getBody();
		final result = body.getStatements()[0].getExpressions()[0];
		assertTrue(result.getTag() == TypedExprTag.NameRead
			&& result.getFieldInfo() != null, "bare nominal field read lost its selected field declaration");
		switch (TypedBodySource.expression(result)) {
			case EIdent("root"):
			case _:
				throw "nominal field value was rewritten as its TreeNode type";
		}
	}

	static function main():Void {
		final filePath = "checks/TypedBodyMain.hx";
		final source = [
			"package demo;",
			"class Helper {",
			"  public static function bump(value:Int):Int return value + 1;",
			"}",
			"class TypedBodyMain {",
			"  static function main() {",
			"    var value:Int = 1;",
			"    var result:Int = Helper.bump(value++);",
			"    value += 2;",
			"    if (result > 0) { value = result; }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule("demo.TypedBodyMain", filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["checks"], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);

		assertTrue(typed.getRevision() == 1, "initial typed module revision must be explicit");
		assertTrue(typed.getTypedClasses().length == 2, "every module-local class must receive typed functions");
		final mainFunction = findFunction(findClass(typed, "TypedBodyMain"), "main");
		final call = expectResultCall(mainFunction.getBody());
		assertTrue(call.getType().getSemanticKey() == "primitive:Int", "resolved call lost its semantic result type");
		assertTrue(call.getPosition() != null, "root expression lost its exact statement position");
		assertTrue(call.getTag() == TypedExprTag.Call, "result initializer was not a structural typed call");
		final declaration = call.getDeclaration();
		assertTrue(declaration != null, "resolved ordinary call did not retain an exact declaration reference");
		assertTrue(declaration.getSignature().getName() == "bump", "wrong exact declaration selected for Helper.bump");
		assertTrue(declaration.getIdentity().getCanonicalKey().indexOf("demo.TypedBodyMain.Helper#static:bump") == 0,
			"call declaration identity was not canonical and stable");
		final callChildren = call.getExpressions();
		assertTrue(callChildren.length == 2, "call argument was lost");
		final argument = callChildren[1];
		assertTrue(argument.getTag() == TypedExprTag.Unary
			&& argument.getUnaryOperator() == HxUnaryOperator.Increment
			&& argument.getUnaryFixity() == HxUnaryFixity.Postfix,
			"nested postfix operator disappeared inside the typed call");
		assertTrue(argument.getPosition() == null, "missing nested expression position was fabricated from its parent");
		final operand = argument.getExpressions()[0];
		assertTrue(operand.getTag() == TypedExprTag.LocalRead
			&& operand.getTexts()[0] == "value", "postfix operand was not a typed local read");
		expectCompoundAssignment(mainFunction.getBody());
		TypedBodyInvariant.assertClasses(typed.getTypedClasses());
		assertTrue(TypedBodyFingerprint.forStatements(TypedBodySource.statements(mainFunction.getBody())) == mainFunction.getBody().getSourceFingerprint(),
			"typed-body source projection changed ordinary syntax before backend cutover");
		assertLoweringNodeSet();
		assertNullableSourceProjection();
		assertInferredConstructorSourceProjection();
		assertStructuralExpressionBlock();
		assertStructuralDoWhileExpression();
		assertNullSafeCallStructure();
		assertAbstractThisAssignment();
		assertStructuralTryCatchExpression();
		assertStructuralTerminalReturnBlock();
		assertStructuralUntypedStatementBlock();
		assertConditionalElseIfStructure();
		assertStrictInstanceMethodCallee();
		assertMethodGenericResultSpecialization();
		assertNominalFieldReadRemainsAValue();
		assertOpaqueGuard();
		assertReturnMacroArgumentStructure();
		assertVariableDeclarationMacroArgumentStructure();
		assertLocalVariableMetadataStructure();
		assertWhileMacroArgumentStructure();
		assertNullCoalescingLoopControlStructure();
		assertLifecycleGuard(typed, mainFunction);
	}
}
