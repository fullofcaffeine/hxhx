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

	static function assertLoweringNodeSet():Void {
		final position = new HxPos(0, 1, 1);
		final intType = TyType.fromHintText("Int");
		final temporary = TypedExpr.temporary("__op0", "Int", TypedExpr.intLiteral(1, intType, null), TyType.fromHintText("Void"), null);
		final assignment = TypedExpr.assign(TypedExpr.localRead("value", intType, null), TypedExpr.localRead("__op0", intType, null), intType, null);
		final block = TypedExpr.block([temporary, assignment], intType, position);
		final sourceFunction = new HxFunctionDecl("lowered", HxVisibility.Private, false, [], "Int", [], "", [], position);
		final typedFunction = new TypedFunction("Main", 0, sourceFunction, null, null,
			new TypedFunctionBody([TypedStmt.expressionStmt(block, position)], TypedBodyFingerprint.forStatements([])));
		TypedBodyInvariant.assertFunction(typedFunction);
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
		assertStructuralExpressionBlock();
		assertStructuralDoWhileExpression();
		assertAbstractThisAssignment();
		assertStructuralTryCatchExpression();
		assertStructuralTerminalReturnBlock();
		assertStructuralUntypedStatementBlock();
		assertConditionalElseIfStructure();
		assertStrictInstanceMethodCallee();
		assertOpaqueGuard();
		assertLifecycleGuard(typed, mainFunction);
	}
}
