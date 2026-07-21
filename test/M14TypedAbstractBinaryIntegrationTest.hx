import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;
import TypedStmt.TypedStmtTag;

/** Focused contract for shared abstract binary selection and lowering. **/
class M14TypedAbstractBinaryIntegrationTest {
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

	static function declarationExpression(expression:TypedExpr, name:String):Null<TypedExpr> {
		final declaration = expression.getDeclaration();
		if (declaration != null && declaration.getSignature().getName() == name)
			return expression;
		for (child in expression.getExpressions()) {
			final found = declarationExpression(child, name);
			if (found != null)
				return found;
		}
		return null;
	}

	static function namedCallCount(expression:TypedExpr, name:String):Int {
		final children = expression.getExpressions();
		var count = expression.getTag() == TypedExprTag.Call && children.length > 0 && children[0].getTexts().indexOf(name) >= 0 ? 1 : 0;
		for (child in children)
			count += namedCallCount(child, name);
		return count;
	}

	static function castCountTo(expression:TypedExpr, semanticKey:String):Int {
		var count = expression.getTag() == TypedExprTag.Cast && expression.getType().getSemanticKey() == semanticKey ? 1 : 0;
		for (child in expression.getExpressions())
			count += castCountTo(child, semanticKey);
		return count;
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

	static function expressionStatementWithDeclaration(main:TypedFunction, name:String):Null<TypedExpr> {
		for (statement in main.getBody().getStatements())
			if (statement.getTag() == TypedStmtTag.Expression && statement.getExpressions().length == 1) {
				final expression = statement.getExpressions()[0];
				if (declarationExpression(expression, name) != null)
					return expression;
			}
		return null;
	}

	static function main():Void {
		final source = [
			"abstract Score(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  public function get():Int return this;",
			"  @:op(A + B) public static function mergeArbitrarily(left:Score, right:Score):Score return new Score(left.get() + right.get());",
			"  @:commutative @:op(A * B) public static function decorateArbitrarily(value:Score, text:String):String return text;",
			"  @:op(A * B) public static function scaleArbitrarily(value:Score, factor:Float):Score return value;",
			"  @:op(A += B) public static function explicitCompoundArbitrarily(value:Score, amount:Int):Score return new Score(value.get() + amount);",
			"  @:op(A - B) public function subtractArbitrarily(amount:Int):Score return new Score(this - amount);",
			"  @:commutative @:op(A / B) public function wrapArbitrarily(text:String):String return text;",
			"}",
			"abstract Fallback(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(A + B) public static function addArbitrarily(value:Fallback, amount:Int):Fallback return new Fallback(value + amount);",
			"}",
			"abstract NullFloat(Null<Float>) from Null<Float> to Null<Float> {",
			"  @:op(A + B) public static inline function addNullable(left:NullFloat, right:Float):Float return right;",
			"}",
			"abstract NativeSum(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(A + B) public static function nativeArbitrarily(left:NativeSum, right:NativeSum):NativeSum;",
			"}",
			"abstract NativeText(String) from String to String {",
			"  public inline function new(value:String) this = value;",
			"  @:op(A + B) public static function appendIntArbitrarily(left:NativeText, right:Int):NativeText;",
			"  @:op(A + B) public static function rejectBoolArbitrarily(left:NativeText, right:Bool):Bool;",
			"}",
			"abstract Slice(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(A / B) public static function trimArbitrarily(text:String, count:Slice):String return text;",
			"}",
			"abstract Mutable(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(A += B) public inline function mutateArbitrarily(amount:Int):Void this += amount;",
			"}",
			"abstract DirectTie(Int) from Int to Int {",
			"  public inline function new(value:Int) this = value;",
			"  @:commutative @:op(A + B) public static function chooseDirect(left:DirectTie, right:Dynamic):Int return left;",
			"}",
			"class FieldHolder {",
			"  public var value:Fallback;",
			"  public function new(value:Fallback) this.value = value;",
			"}",
			"class PropertyHolder {",
			"  var stored:Fallback;",
			"  public var value(get, set):Fallback;",
			"  public function new(value:Fallback) stored = value;",
			"  function get_value():Fallback return stored;",
			"  function set_value(next:Fallback):Fallback return stored = next;",
			"}",
			"abstract W(Int) from Int {}",
			"class HelperMacros { public static function typeError(value:Dynamic):Bool return false; }",
			"class Main {",
			"  static var W:Int = 2;",
			"  static function makeFieldHolder(value:Fallback):FieldHolder return new FieldHolder(value);",
			"  static function main() {",
			"  var left:Score = new Score(2);",
			"  var right:Score = new Score(3);",
			"  var direct = left + right;",
			"  var reversed = 'x' * left;",
			"  var widened = left * 2;",
			"  var explicitResult:Score = (left += 4);",
			"  var instanceResult = left - 1;",
			"  var reversedInstance = 'z' / left;",
			"  var stringFallback = left + '!';",
			"  var uppercaseFieldControl = W + 1;",
			"  var localFunctionText = '';",
			"  function nextText() { localFunctionText += 'b'; return localFunctionText; }",
			"  var localFunctionRight = left * nextText();",
			"  var localFunctionReversed = nextText() * left;",
			"  var fallback:Fallback = new Fallback(5);",
			"  var fallbackResult:Fallback = (fallback += 6);",
			"  var nullable:NullFloat = null;",
			"  var nullableResult:NullFloat = (nullable += nullable);",
			"  var fieldHolder = new FieldHolder(new Fallback(7));",
			"  var fieldResult:Fallback = (fieldHolder.value += 2);",
			"  var sideEffectFieldResult:Fallback = (makeFieldHolder(new Fallback(8)).value += 3);",
			"  var propertyHolder = new PropertyHolder(new Fallback(9));",
			"  var propertyResult:Fallback = (propertyHolder.value += 4);",
			"  var nativeLeft:NativeSum = new NativeSum(7);",
			"  var nativeRight:NativeSum = new NativeSum(8);",
			"  var nativeResult = nativeLeft + nativeRight;",
			"  var nativeText:NativeText = new NativeText('value');",
			"  var nativeTextResult = nativeText + 4;",
			"  var typeTestControl = nativeTextResult is String;",
			"  var invalidNativeProbe = HelperMacros.typeError(nativeText + true);",
			"  var validNativeProbe = HelperMacros.typeError(nativeText + 4);",
			"  var count:Slice = new Slice(2);",
			"  var rightOwned = 'word' / count;",
			"  var mutable:Mutable = new Mutable(9);",
			"  mutable += 3;",
			"  var directTieLeft:DirectTie = new DirectTie(1);",
			"  var directTieRight:DirectTie = new DirectTie(2);",
			"  var directTieResult = directTieLeft + directTieRight;",
			"} }",
		].join("\n");
		final typed = typedModule(source, "Main.hx");
		final main = mainFunction(typed);

		final direct = initializer(main, "direct");
		assertTrue(direct.getTag() == TypedExprTag.Block
			&& declarationExpression(direct, "mergeArbitrarily") != null
			&& !containsTag(direct, TypedExprTag.Binary),
			"ordinary abstract binary operation did not become an exact ordered call");

		final reversed = initializer(main, "reversed");
		final reversedCall = declarationExpression(reversed, "decorateArbitrarily");
		assertTrue(reversed.getTag() == TypedExprTag.Block && reversedCall != null && reversedCall.getExpressions().length == 3,
			"commutative abstract operation did not become an exact call");
		assertTrue(reversedCall.getExpressions()[1].getType().getSemanticKey() == "nominal:Main.Score"
			&& reversedCall.getExpressions()[2].getType().getSemanticKey() == "primitive:String",
			"commutative call did not reverse declaration arguments after source-order temporaries");

		final widened = initializer(main, "widened");
		final widenedCall = declarationExpression(widened, "scaleArbitrarily");
		assertTrue(widenedCall != null
			&& widenedCall.getExpressions()[2].getTag() == TypedExprTag.Cast
			&& widenedCall.getExpressions()[2].getType().getDisplay() == "Float",
			"numeric widening was not made explicit before the exact helper call");

		final explicitResult = initializer(main, "explicitResult");
		assertTrue(declarationExpression(explicitResult, "explicitCompoundArbitrarily") != null
			&& !containsTag(explicitResult, TypedExprTag.Assign),
			"explicit compound helper received invented writeback");

		final fallbackResult = initializer(main, "fallbackResult");
		assertTrue(declarationExpression(fallbackResult, "addArbitrarily") != null && containsTag(fallbackResult, TypedExprTag.Assign),
			"base-operator compound fallback did not expose its shared writeback schedule");
		final nullableResult = initializer(main, "nullableResult");
		final nullableCall = declarationExpression(nullableResult, "addNullable");
		assertTrue(nullableCall != null
			&& nullableCall.getExpressions().length == 3
			&& nullableCall.getExpressions()[2].getTag() == TypedExprTag.Cast
			&& nullableCall.getExpressions()[2].getType().getSemanticKey() == "primitive:Float",
			"declared abstract-to conversion did not adapt the compound right operand");
		assertTrue(containsTag(nullableResult, TypedExprTag.Assign) && castCountTo(nullableResult, "nominal:Main.NullFloat") == 1,
			"declared abstract-from conversion did not adapt the helper result before shared writeback");

		final fieldResult = initializer(main, "fieldResult");
		assertTrue(declarationExpression(fieldResult, "addArbitrarily") != null && containsTag(fieldResult, TypedExprTag.Assign),
			"field compound fallback did not retain an explicit read/call/write schedule");
		final sideEffectFieldResult = initializer(main, "sideEffectFieldResult");
		assertTrue(namedCallCount(sideEffectFieldResult, "makeFieldHolder") == 1
			&& declarationExpression(sideEffectFieldResult, "addArbitrarily") != null
			&& containsTag(sideEffectFieldResult, TypedExprTag.Assign),
			"field compound fallback did not evaluate its side-effecting receiver exactly once");
		final propertyResult = initializer(main, "propertyResult");
		assertTrue(declarationExpression(propertyResult, "get_value") != null
			&& declarationExpression(propertyResult, "addArbitrarily") != null
			&& declarationExpression(propertyResult, "set_value") != null,
			"property compound fallback did not expose its getter, exact helper, and setter calls");

		final nativeResult = initializer(main, "nativeResult");
		assertTrue(nativeResult.getTag() == TypedExprTag.Block
			&& containsTag(nativeResult, TypedExprTag.Binary)
			&& !containsTag(nativeResult, TypedExprTag.Call),
			"bodyless declaration did not authorize one ordinary carrier operation");

		final nativeTextResult = initializer(main, "nativeTextResult");
		assertTrue(nativeTextResult.getTag() == TypedExprTag.Block
			&& nativeTextResult.getType().getSemanticKey() == "nominal:Main.NativeText"
			&& containsTag(nativeTextResult, TypedExprTag.Binary),
			"bodyless String-plus-Int declaration did not preserve its String carrier and abstract result");
		assertTrue(initializer(main, "typeTestControl").getTag() == TypedExprTag.Binary,
			"ordinary type-test syntax was mistaken for a surviving abstract operator");
		assertTrue(initializer(main, "invalidNativeProbe").getTag() == TypedExprTag.BoolValue
			&& initializer(main, "invalidNativeProbe").getBoolValue(),
			"typeError did not capture an incompatible bodyless binary result carrier");
		assertTrue(initializer(main, "validNativeProbe").getTag() == TypedExprTag.BoolValue
			&& !initializer(main, "validNativeProbe").getBoolValue(),
			"typeError reported a valid bodyless String-plus-Int declaration as invalid");

		final rightOwned = initializer(main, "rightOwned");
		assertTrue(declarationExpression(rightOwned, "trimArbitrarily") != null, "operator catalog did not find an abstract owned by the right operand");

		final instanceResult = initializer(main, "instanceResult");
		assertTrue(declarationExpression(instanceResult, "subtractArbitrarily") != null,
			"non-inline instance operator did not become an exact instance-semantic call");

		final reversedInstance = initializer(main, "reversedInstance");
		final reversedInstanceCall = declarationExpression(reversedInstance, "wrapArbitrarily");
		assertTrue(reversedInstanceCall != null
			&& reversedInstanceCall.getExpressions().length == 2
			&& reversedInstanceCall.getExpressions()[0].getTag() == TypedExprTag.FieldRead
			&& reversedInstanceCall.getExpressions()[0].getExpressions()[0].getType().getSemanticKey() == "nominal:Main.Score"
			&& reversedInstanceCall.getExpressions()[1].getType().getSemanticKey() == "primitive:String",
			"commutative instance call did not restore declaration receiver/argument order");

		final stringFallback = initializer(main, "stringFallback");
		assertTrue(stringFallback.getTag() == TypedExprTag.Binary
			&& stringFallback.getType().getDisplay() == "String"
			&& declarationExpression(stringFallback, "mergeArbitrarily") == null,
			"ordinary String concatenation was mistaken for an unsupported abstract overload");

		final uppercaseFieldControl = initializer(main, "uppercaseFieldControl");
		assertTrue(uppercaseFieldControl.getTag() == TypedExprTag.Binary && uppercaseFieldControl.getType().getDisplay() == "Int",
			"an uppercase field in the current class was mistaken for an abstract type name: tag="
			+ Std.string(uppercaseFieldControl.getTag())
			+ " type="
			+ uppercaseFieldControl.getType().getDisplay());

		final localFunctionRight = declarationExpression(initializer(main, "localFunctionRight"), "decorateArbitrarily");
		final localFunctionReversed = declarationExpression(initializer(main, "localFunctionReversed"), "decorateArbitrarily");
		final environment = main.getEnvironment();
		final nextTextType = environment == null ? null : environment.resolveSymbol("nextText").getType();
		assertTrue(localFunctionRight != null
			&& localFunctionRight.getExpressions()[2].getType().getDisplay() == "String"
			&& localFunctionReversed != null
			&& localFunctionReversed.getExpressions()[2].getType().getDisplay() == "String"
			&& nextTextType != null
			&& nextTextType.isFunction()
			&& nextTextType.getFunctionReturn().getDisplay() == "String",
			"unannotated local-function calls lost their inferred String result before abstract operator binding");

		final mutable = expressionStatementWithDeclaration(main, "mutateArbitrarily");
		assertTrue(mutable == null, "inline instance helper survived as a declaration call for backend reinterpretation");
		var sawInlineMutation = false;
		for (statement in main.getBody().getStatements())
			if (statement.getTag() == TypedStmtTag.Expression && statement.getExpressions().length == 1) {
				final expression = statement.getExpressions()[0];
				if (expression.getType().isVoid()
					&& expression.getTag() == TypedExprTag.Block
					&& containsTag(expression, TypedExprTag.CompoundAssign))
					sawInlineMutation = true;
			}
		assertTrue(sawInlineMutation, "inline instance compound helper did not expose its carrier mutation in a typed block");

		assertTrue(declarationExpression(initializer(main, "directTieResult"), "chooseDirect") != null,
			"equally ranked direct/commutative matching did not prefer the source orientation");

		typingFailure([
			"abstract InvalidNativeText(String) from String {",
			"  public inline function new(value:String) this = value;",
			"  @:op(A + B) public static function reject(left:InvalidNativeText, right:Bool):Bool;",
			"}",
			"class Main { static function main() { var value = new InvalidNativeText('x'); var result = value + true; } }",
		].join("\n"), "Unsupported abstract binary conversion from String to Bool");
		typingFailure([
			"abstract Missing(Int) { public inline function new(value:Int) this = value; }",
			"class Main { static function main() { var value:Missing = new Missing(1); var result = value * 2; } }",
		].join("\n"), "No applicable abstract binary operator");
		typingFailure([
			"abstract Ambiguous(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(A + B) public static function first(left:Ambiguous, right:Int):Ambiguous return left;",
			"  @:op(A + B) public static function second(left:Ambiguous, right:Int):Ambiguous return left;",
			"}",
			"class Main { static function main() { var value:Ambiguous = new Ambiguous(1); var result = value + 2; } }",
		].join("\n"), "Ambiguous abstract binary operator");
		typingFailure([
			"abstract Convert(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(A * B) public static function onlyFloat(left:Convert, right:Float):Convert return left;",
			"}",
			"class Main { static function main() { var value:Convert = new Convert(1); var result = value * 'bad'; } }",
		].join("\n"), "requires Convert and Float");
		typingFailure([
			"abstract NoTo(Null<Float>) from Null<Float> {",
			"  @:op(A + B) public static function add(left:NoTo, right:Float):Float return right;",
			"}",
			"class Main { static function main() { var value:NoTo = null; value += value; } }",
		].join("\n"), "No applicable abstract binary operator");
		typingFailure([
			"abstract NoFrom(Null<Float>) to Null<Float> {",
			"  @:op(A + B) public static function add(left:NoFrom, right:Float):Float return right;",
			"}",
			"class Main { static function main() { var value:NoFrom = cast null; value += value; } }",
		].join("\n"), "No applicable abstract binary operator");
		typingFailure([
			"abstract Generic<T>(Int) { @:op(A + B) public static function add(left:Generic<T>, right:Generic<T>):Generic<T> return left; }",
			"class Main { static function main(left:Generic<Int>, right:Generic<Int>) { var result = left + right; } }",
		].join("\n"), "Generic abstract binary operator is not supported yet");
		typingFailure([
			"abstract BadArity(Int) { @:op(A + B) public static function add(left:BadArity):BadArity return left; }",
			"class Main { static function main() {} }",
		].join("\n"), "requires exactly two explicit arguments");
		typingFailure([
			"abstract MissingOwner(Int) { @:op(A + B) public static function add(left:Int, right:Int):Int return left + right; }",
			"class Main { static function main() {} }",
		].join("\n"), "must retain owning abstract type");
		typingFailure([
			"abstract Duplicate(Int) {",
			"  @:op(A + B) @:op(A + B) public static function add(left:Duplicate, right:Duplicate):Duplicate return left;",
			"}",
			"class Main { static function main() {} }",
		].join("\n"), "Duplicate binary @:op metadata");
	}
}
