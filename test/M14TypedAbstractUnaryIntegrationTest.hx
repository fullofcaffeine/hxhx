import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;

/** Focused contract for shared exact abstract-unary selection and lowering. **/
class M14TypedAbstractUnaryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function typedModule(source:String, filePath:String):TypedModule {
		final parsed = ParserStage.parse(source, filePath);
		final resolved = new ResolvedModule(haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(filePath)), filePath, parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		return TyperStage.typeResolvedModule(resolved, index, loader);
	}

	static function mainFunction(module:TypedModule):TypedFunction {
		for (typedClass in module.getTypedClasses())
			if (HxClassDecl.getName(typedClass.getSourceDeclaration()) == "Main")
				for (typedFunction in typedClass.getFunctions())
					if (HxFunctionDecl.getName(typedFunction.getSourceDeclaration()) == "main")
						return typedFunction;
		throw "missing Main.main";
	}

	static function initializer(typedFunction:TypedFunction, name:String):TypedExpr {
		for (statement in typedFunction.getBody().getStatements()) {
			final names = statement.getNames();
			if (names.length > 0 && names[0] == name) {
				final expressions = statement.getExpressions();
				if (expressions.length == 1)
					return expressions[0];
			}
		}
		throw "missing initializer for " + name;
	}

	static function containsTag(expression:TypedExpr, tag:TypedExprTag):Bool {
		if (expression.getTag() == tag)
			return true;
		for (child in expression.getExpressions())
			if (containsTag(child, tag))
				return true;
		return false;
	}

	static function inlineBlock(expression:TypedExpr):TypedExpr {
		if (expression.getTag() == TypedExprTag.Cast)
			return expression.getExpressions()[0];
		return expression;
	}

	static function typingFailure(source:String, expected:String):Void {
		var message:Null<String> = null;
		try {
			typedModule(source, "Failure.hx");
		} catch (error:TyperError) {
			message = error.toString();
		}
		assertTrue(message != null && message.indexOf(expected) >= 0, "expected typer failure containing '"
			+ expected
			+ "', got "
			+ Std.string(message));
	}

	static function crossModuleInlineTest():Void {
		final helperSource = [
			"abstract Step(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public inline function advance():Step { this += 10; return cast this; }",
			"}",
		].join("\n");
		final mainSource = [
			"import Ops.Step;",
			"class Main { static function main() {",
			"  var value:Step = new Step(2);",
			"  var result:Step = ++value;",
			"} }",
		].join("\n");
		final helperResolved = new ResolvedModule("Ops", "Ops.hx", ParserStage.parse(helperSource, "Ops.hx"));
		final mainResolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(mainSource, "Main.hx"));
		final resolved = [helperResolved, mainResolved];
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(["."], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready(resolved);
		final provisional = [
			TyperStage.typeResolvedModule(helperResolved, index, loader, true),
			TyperStage.typeResolvedModule(mainResolved, index, loader, true),
		];
		final sealed = TypedAbstractUnaryLowering.lowerModules(provisional, index);
		final result = initializer(mainFunction(sealed[1]), "result");
		assertTrue(result.getTag() == TypedExprTag.Cast
			&& inlineBlock(result).getTag() == TypedExprTag.Block
			&& !containsTag(result, TypedExprTag.Unary),
			"program sealing did not inline the exact helper body declared in another module");
	}

	static function main():Void {
		final source = [
			"class Carrier {",
			"  public var value:Int;",
			"  public function new(value:Int) this.value = value;",
			"}",
			"abstract ClassNeg(Carrier) {",
			"  public inline function new(value:Carrier) this = value;",
			"  @:op(-A) public static function arbitraryClassNeg(value:ClassNeg):ClassNeg return value;",
			"}",
			"abstract PrimitiveNeg(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(-A) public function arbitraryPrimitiveNeg():PrimitiveNeg return new PrimitiveNeg(-this);",
			"}",
			"abstract PrefixValue(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public inline function arbitraryPrefix():PrefixValue { this += 30; return cast this; }",
			"  @:op(A++) public inline function arbitraryPostfix():PrefixValue { var old = this; this += 1; return cast old; }",
			"}",
			"class Ordinary {",
			"  public function new() {}",
			"  public function arbitraryPrimitiveNeg():Ordinary return this;",
			"}",
			"class Main {",
			"  static function main() {",
			"    var classValue:ClassNeg = new ClassNeg(new Carrier(1));",
			"    var classResult = -classValue;",
			"    var primitiveValue:PrimitiveNeg = new PrimitiveNeg(12);",
			"    var primitiveResult = -primitiveValue;",
			"    var prefixValue:PrefixValue = new PrefixValue(3);",
			"    var prefixResult = ++prefixValue;",
			"    var postfixResult = prefixValue++;",
			"    var ordinaryNumber = -7;",
			"    var ordinaryObject = new Ordinary();",
			"    var ordinaryControl = -ordinaryObject;",
			"  }",
			"}",
		].join("\n");
		final typed = typedModule(source, "Main.hx");
		final main = mainFunction(typed);

		final classResult = initializer(main, "classResult");
		final classCall = classResult.getExpressions()[0];
		assertTrue(classResult.getTag() == TypedExprTag.Cast && classCall.getTag() == TypedExprTag.Call,
			"class-backed unary minus did not become a carrier-preserving exact call");
		assertTrue(classCall.getDeclaration() != null && classCall.getDeclaration().getSignature().getName() == "arbitraryClassNeg",
			"class-backed helper was not selected by @:op metadata");
		assertTrue(classResult.getType().getSemanticKey() == "nominal:Main.ClassNeg", "class-backed call lost its declared result type");

		final primitiveResult = initializer(main, "primitiveResult");
		final primitiveCall = primitiveResult.getExpressions()[0];
		assertTrue(primitiveResult.getTag() == TypedExprTag.Cast && primitiveCall.getTag() == TypedExprTag.Call,
			"primitive-backed unary minus did not become a carrier-preserving exact instance call");
		assertTrue(primitiveCall.getDeclaration() != null
			&& primitiveCall.getDeclaration().getSignature().getName() == "arbitraryPrimitiveNeg",
			"primitive-backed helper was selected by spelling or carrier instead of declaration identity");

		final prefixResult = initializer(main, "prefixResult");
		final prefixBlock = inlineBlock(prefixResult);
		assertTrue(prefixResult.getTag() == TypedExprTag.Cast
			&& prefixResult.getType().getSemanticKey() == "nominal:Main.PrefixValue"
			&& prefixBlock.getTag() == TypedExprTag.Block
			&& !containsTag(prefixResult, TypedExprTag.Unary),
			"inline prefix helper was not completely lowered before backend emission");
		final prefixChildren = prefixBlock.getExpressions();
		assertTrue(prefixChildren.length == 2
			&& prefixChildren[0].getTag() == TypedExprTag.CompoundAssign
			&& prefixChildren[1].getTag() == TypedExprTag.Cast,
			"inline prefix mutation/result schedule was not explicit");

		final postfixResult = initializer(main, "postfixResult");
		final postfixBlock = inlineBlock(postfixResult);
		final postfixChildren = postfixBlock.getExpressions();
		assertTrue(postfixResult.getTag() == TypedExprTag.Cast
			&& postfixBlock.getTag() == TypedExprTag.Block
			&& postfixChildren.length == 3
			&& postfixChildren[0].getTag() == TypedExprTag.Temporary
			&& postfixChildren[1].getTag() == TypedExprTag.CompoundAssign
			&& postfixChildren[2].getTag() == TypedExprTag.Cast,
			"postfix result was inferred from spelling instead of the helper's saved-old-value body");

		assertTrue(initializer(main, "ordinaryNumber").getTag() == TypedExprTag.Unary,
			"ordinary numeric unary behavior was routed through the abstract catalog");
		final ordinaryControl = initializer(main, "ordinaryControl");
		assertTrue(ordinaryControl.getTag() == TypedExprTag.Unary && ordinaryControl.getDeclaration() == null,
			"ordinary class acquired operator behavior from a similarly named method");

		typingFailure([
			"abstract Missing(Int) { public inline function new(value:Int) this = value; }",
			"class Main { static function main() { var value:Missing = new Missing(1); var result = -value; } }",
		].join("\n"), "No applicable abstract unary operator");
		typingFailure([
			"abstract Ambiguous(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(-A) public static function first(value:Ambiguous):Ambiguous return value;",
			"  @:op(-A) public static function second(value:Ambiguous):Ambiguous return value;",
			"}",
			"class Main { static function main() { var value:Ambiguous = new Ambiguous(1); var result = -value; } }",
		].join("\n"), "Ambiguous abstract unary operator");
		typingFailure([
			"abstract Generic<T>(Int) {",
			"  @:op(-A) public static function arbitrary(value:Generic<T>):Generic<T> return value;",
			"}",
			"class Main { static function main(value:Generic<Int>) { var result = -value; } }",
		].join("\n"), "Generic abstract unary operator is not supported yet");
		crossModuleInlineTest();
	}
}
