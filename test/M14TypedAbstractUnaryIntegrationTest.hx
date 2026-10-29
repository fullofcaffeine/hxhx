import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;
import TypedStmt.TypedStmtTag;

/** Focused contract for shared exact abstract-unary selection and lowering. **/
class M14TypedAbstractUnaryIntegrationTest {
	/** Every conversion in this property schedule is compiler-created from its selected Int backing. */
	static function assertPropertyStorageProof(expression:TypedExpr):Void {
		if (expression.getTag() == Cast)
			assertTrue(expression.isRepresentationPreservingCast(), "property update lost its exact backing storage proof");
		for (child in expression.getExpressions())
			assertPropertyStorageProof(child);
	}

	/** Haxe 4.3.7 accepts this during ordinary typing before null-safety analysis. **/
	static function hostNullablePostfix(value:Null<Int>):Null<Int> {
		return value++;
	}

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

	static function containsDeclaration(expression:TypedExpr, name:String):Bool
		return declarationExpression(expression, name) != null;

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

	static function inlineHelperShadowingTest():Void {
		final source = [
			"abstract Shadowed(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public inline function advance():Shadowed {",
			"    var value:Int = 1;",
			"    { var value:String = 'inner'; value; }",
			"    value += 1;",
			"    this += value;",
			"    return cast this;",
			"  }",
			"}",
			"class Main { static function main() {",
			"  var target:Shadowed = new Shadowed(2);",
			"  var result:Shadowed = ++target;",
			"} }",
		].join("\n");
		final module = typedModule(source, "Main.hx");
		final result = inlineBlock(initializer(mainFunction(module), "result"));
		final expressions = result.getExpressions();
		assertTrue(result.getTag() == TypedExprTag.Block
			&& expressions.length >= 5, "shadowed inline helper did not become an explicit ordered block");
		final outerBindings = expressions[0].getLocalBindings();
		final innerBindings = expressions[1].getLocalBindings();
		assertTrue(expressions[0].getTag() == TypedExprTag.Temporary
			&& outerBindings.length == 1
			&& outerBindings[0].getType().getSemanticKey() == "primitive:Int",
			"outer helper local lost its exact temporary binding");
		assertTrue(expressions[1].getTag() == TypedExprTag.Temporary
			&& innerBindings.length == 1
			&& innerBindings[0].getType().getSemanticKey() == "primitive:String",
			"inner helper local lost its exact temporary binding");
		final implementationRevision = CompilerTypedModuleRevision.fromTypedModule(module).implementationRevision;
		assertTrue(implementationRevision.indexOf("typed-abstract-unary-v3") >= 0
			&& implementationRevision.indexOf(outerBindings[0].getCanonicalIdentity()) >= 0,
			"typed-module implementation revision omitted the unary pass or generated binding identity");
		assertTrue(!outerBindings[0].getIdentity().equals(innerBindings[0].getIdentity()), "shadowed helper locals received the same temporary identity");
		final innerReadBindings = expressions[2].getLocalBindings();
		assertTrue(expressions[2].getTag() == TypedExprTag.LocalRead
			&& innerReadBindings.length == 1
			&& innerReadBindings[0].getIdentity().equals(innerBindings[0].getIdentity()),
			"read inside the nested helper block did not select the inner binding");
		final outerUpdate = expressions[3];
		final outerUpdateBindings = outerUpdate.getExpressions()[0].getLocalBindings();
		assertTrue(outerUpdate.getTag() == TypedExprTag.CompoundAssign
			&& outerUpdateBindings.length == 1
			&& outerUpdateBindings[0].getIdentity().equals(outerBindings[0].getIdentity()),
			"read after the nested helper block did not return to the outer binding");
	}

	/** A selected operator's storage guarantee must not authorize unrelated result types or authored casts. */
	static function storageGuaranteeTests():Void {
		final source = [
			"abstract Bits(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(~A) private function complement():Bits;",
			"}",
			"abstract Other(String) {}",
			"abstract DifferentResult(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(~A) private function complement():Other;",
			"}",
			"class Main { static function main() {",
			"  var value = new Bits(7);",
			"  var selected = ~value;",
			"  var checked = cast(value, Int);",
			"  var unchecked:Int = cast value;",
			"  var uncheckedBack:Bits = cast 7;",
			"  var uncheckedSame:Bits = cast value;",
			"  var different = ~new DifferentResult(7);",
			"} }",
		].join("\n");
		final main = mainFunction(typedModule(source, "Main.hx"));
		final selected = initializer(main, "selected");
		final operandView = selected.getExpressions()[0].getExpressions()[0];
		assertTrue(selected.isRepresentationPreservingCast() && operandView.isRepresentationPreservingCast(),
			"bodyless operator without conversion headers lost its selected storage guarantee");
		for (name in ["checked", "unchecked", "uncheckedBack", "uncheckedSame"])
			assertTrue(initializer(main, name).getTag() == TypedExprTag.Cast && !initializer(main, name).isRepresentationPreservingCast(),
				"authored cast acquired a selected operator's storage guarantee: " + name);
		final different = initializer(main, "different");
		assertTrue(different.getType().getSemanticKey() == "nominal:Main.Other" && !different.isRepresentationPreservingCast(),
			"operator with a different result acquired an unsupported storage guarantee");
		assertTrue(!selected.withType(TyType.fromHintText("String")).isRepresentationPreservingCast(),
			"changing the result type retained an obsolete storage guarantee");
		assertTrue(!operandView.withExpressions([operandView.getExpressions()[0].withType(TyType.fromHintText("String"))]).isRepresentationPreservingCast(),
			"changing the operand type retained an obsolete storage guarantee");
	}

	/** Same backing types and same declaration names cannot replace the selected declaration's authority. */
	static function inlineStorageAuthorityTests():Void {
		final source = 'abstract Writer(Int) {
@:op(++A) public inline function update():Writer { this += 1; return cast this; }
}
abstract Other(Int) {
@:op(++A) public inline function update():Other { this += 1; return cast this; }
}
class Main { static function main():Void {} }';
		function index():TyperIndex {
			final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
			return TyperIndex.build([resolved]);
		}
		final declarations = index();
		final owner = declarations.getAbstractByFullName("Main.Writer");
		final declaration = owner.getAllUnaryOperators()[0].getDeclaration();
		final receiver = TyType.nominal(owner.getIdentity(), []);
		final allocator = new TyCompilerTemporaryAllocator("inline-storage-test", "authority-v1", "__inline_storage_test_");
		final binding = allocator.allocate("receiver", receiver);
		final place:TypedAbstractUnaryInlinePlace.TypedUnaryPlace = {
			prefix: [],
			read: type -> TypedExpr.localRead(binding.getSourceName(), type, null, binding),
			write: value -> TypedExpr.assign(TypedExpr.localRead(binding.getSourceName(), receiver, null, binding), value, value.getType(), null)
		};
		function prepare(selected:TyDeclarationInfo, actual:TyType):TypedAbstractUnaryInlinePlace.TypedInlineUnaryPlace {
			return TypedAbstractUnaryInlinePlace.prepare({
				place: place,
				receiver: actual,
				abstractInfo: owner,
				declaration: selected,
				allocator: allocator
			});
		}
		function rejects(action:Void->Void, fragment:String):Void {
			try {
				action();
			} catch (failure:haxe.Exception) {
				if (failure.message.indexOf(fragment) >= 0)
					return;
				throw failure;
			}
			throw "inline unary storage accepted unrelated authority";
		}
		final selected = prepare(declaration, receiver);
		final read = selected.read(TyType.fromHintText("Int"));
		assertTrue(read.isRepresentationPreservingCast()
			&& read.getExpressions()[0].getType().getSemanticKey() == receiver.getSemanticKey()
			&& read.getExpressions()[0].getLocalBindings()[0] == binding,
			"backing read changed the caller binding instead of making an explicit view");
		final other = declarations.getAbstractByFullName("Main.Other");
		rejects(() -> prepare(other.getAllUnaryOperators()[0].getDeclaration(), receiver), "exact abstract declaration");
		rejects(() -> prepare(declaration, TyType.nominal(other.getIdentity(), [])), "exact abstract declaration");
		rejects(() -> prepare(index().getAbstractByFullName("Main.Writer")
			.getAllUnaryOperators()[0].getDeclaration(), receiver), "exact abstract declaration");
		rejects(() -> selected.read(TyType.fromHintText("String")), "selected abstract backing");
		rejects(() -> selected.write(TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), null)), "selected abstract backing");
	}

	/** Same-abstract method calls retain storage; methods on a backing object still receive that object. */
	static function inlineMethodReceiverTests():Void {
		final nested = mainFunction(typedModule('abstract Counter(Int) from Int to Int {
public inline function bump():Int { this = this + 1; return this; }
@:op(A++) public inline function post():Int { var old = this; bump(); return old; }
}
class Main { static function main():Void { var value:Counter = 8; var result = value++; } }', "Main.hx"));
		assertTrue(declarationExpression(initializer(nested, "result"), "bump") == null,
			"nested inline method did not consume the unary helper's writable receiver");
		final backing = mainFunction(typedModule('class Payload {
public function new() {}
public function read():Int return 7;
}
abstract Wrapper(Payload) from Payload {
@:op(-A) public inline function negate():Int return this.read();
}
class Main { static function main():Void { var value:Wrapper = new Payload(); var result = -value; } }', "Main.hx"));
		final call = declarationExpression(initializer(backing, "result"), "read");
		assertTrue(call != null && call.getTag() == Call && call.getDeclaration().getOwner().getCanonicalName() == "Main.Payload",
			"backing object call changed its selected declaration");
		final receiver = call.getExpressions()[0].getExpressions()[0];
		assertTrue(receiver.getType().getSemanticKey() == "nominal:Main.Payload"
			&& receiver.getTag() == Cast
			&& receiver.getExpressions()[0].getType().getSemanticKey() == "nominal:Main.Wrapper",
			"backing object method borrowed the abstract's writable receiver instead of its backing view");
	}

	/** The old backing value is saved before the RHS, while the read and write keep one source binding. */
	static function assertInlineStorageUpdate(expression:TypedExpr, owner:String, amount:Int):Void {
		final children = expression.getExpressions();
		assertTrue(expression.getTag() == TypedExprTag.Block
			&& children.length == 2
			&& children[0].getTag() == TypedExprTag.Temporary
			&& children[1].getTag() == TypedExprTag.Cast,
			"inline update lost its old-value snapshot or completed write result");
		final snapshot = children[0];
		final before = snapshot.getExpressions()[0];
		final original = before.getExpressions()[0];
		final assignment = children[1].getExpressions()[0];
		assertTrue(before.getTag() == TypedExprTag.Cast
			&& before.isRepresentationPreservingCast()
			&& before.getType().getSemanticKey() == "primitive:Int"
			&& original.getTag() == TypedExprTag.LocalRead
			&& original.getType().getSemanticKey() == owner
			&& original.getLocalBindings()[0].getType().getSemanticKey() == owner
			&& assignment.getTag() == TypedExprTag.Assign
			&& assignment.getType().getSemanticKey() == owner,
			"inline update erased the original abstract binding or lost its backing read");
		final destination = assignment.getExpressions()[0];
		final written = assignment.getExpressions()[1];
		assertTrue(destination.getTag() == TypedExprTag.LocalRead
			&& destination.getLocalBindings()[0].getIdentity().equals(original.getLocalBindings()[0].getIdentity())
			&& written.getTag() == TypedExprTag.Cast
			&& written.isRepresentationPreservingCast()
			&& written.getType().getSemanticKey() == owner,
			"inline update changed its caller destination or lost the completed storage conversion");
		final operation = written.getExpressions()[0];
		assertTrue(operation.getTag() == TypedExprTag.Binary
			&& operation.getTexts()[0] == "+"
			&& operation.getType().getSemanticKey() == "primitive:Int"
			&& operation.getExpressions()[0].getLocalBindings()[0].getIdentity().equals(snapshot.getLocalBindings()[0].getIdentity())
			&& operation.getExpressions()[1].getTag() == TypedExprTag.IntValue
			&& operation.getExpressions()[1].getIntValue() == amount,
			"inline update did not compute from the saved old value and the original RHS");
	}

	static function main():Void {
		storageGuaranteeTests();
		inlineStorageAuthorityTests();
		inlineMethodReceiverTests();
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
			"abstract PrefixOnly(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public static function prefix(value:PrefixOnly):PrefixOnly return value;",
			"}",
			"abstract VoidPrefix(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public inline function mutateWithoutResult() { ++this; }",
			"}",
			"abstract NativeBits(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(~A) private function complement():NativeBits;",
			"}",
			"abstract NativeStaticBits(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(~A) private static function complement(value:NativeStaticBits):NativeStaticBits;",
			"}",
			"class HelperMacros { public static function typeError(value:Dynamic):Bool return false; }",
			"class PropertyHolder {",
			"  var stored:PrefixValue;",
			"  public var value(get, set):PrefixValue;",
			"  public function new(value:Int) stored = new PrefixValue(value);",
			"  function get_value():PrefixValue return stored;",
			"  function set_value(value:PrefixValue):PrefixValue return stored = value;",
			"}",
			"class Ordinary {",
			"  public function new() {}",
			"  public function arbitraryPrimitiveNeg():Ordinary return this;",
			"}",
			"class Main {",
			"  static function shouldFail(value:Dynamic):Void {}",
			"  static function main() {",
			"    var classValue:ClassNeg = new ClassNeg(new Carrier(1));",
			"    var classResult = -classValue;",
			"    var primitiveValue:PrimitiveNeg = new PrimitiveNeg(12);",
			"    var primitiveResult = -primitiveValue;",
			"    var prefixValue:PrefixValue = new PrefixValue(3);",
			"    var prefixResult = ++prefixValue;",
			"    var postfixResult = prefixValue++;",
			"    var propertyHolder = new PropertyHolder(5);",
			"    var propertyPrefix:PrefixValue = ++propertyHolder.value;",
			"    var propertyPostfix:PrefixValue = propertyHolder.value++;",
			"    var probeValue = new PrefixOnly(1);",
			"    var missingLogicalProbe = HelperMacros.typeError(!probeValue);",
			"    var wrongFixityProbe = HelperMacros.typeError(probeValue++);",
			"    var validProbe = HelperMacros.typeError(-7);",
			"    var voidPrefix = new VoidPrefix(8);",
			"    ++voidPrefix;",
			"    var nativeBits = new NativeBits(5);",
			"    var nativeBitsResult = ~nativeBits;",
			"    var nativeStaticBits = new NativeStaticBits(6);",
			"    var nativeStaticBitsResult = ~nativeStaticBits;",
			"    var ordinaryNumber = -7;",
			"    var ordinaryObject = new Ordinary();",
			"    var ordinaryControl = -ordinaryObject;",
			"    var nullableValue:Null<Int> = null;",
			"    var nullablePostfixResult = nullableValue++;",
			"    var nullablePrefixResult = ++nullableValue;",
			"    shouldFail(nullableValue++);",
			"    var nullableCompoundResult = (nullableValue += 1);",
			"    var nullableFloat:Null<Float> = 1.5;",
			"    var nullableFloatPrefixResult = --nullableFloat;",
			"    var nestedValue:Null<Null<Int>> = 4;",
			"    var nestedCopy = nestedValue;",
			"    var nestedPostfixResult = nestedValue++;",
			"  }",
			"}",
		].join("\n");
		final typed = typedModule(source, "Main.hx");
		final main = mainFunction(typed);

		final classResult = initializer(main, "classResult");
		final classCall = classResult.getExpressions()[0];
		assertTrue(classResult.getTag() == TypedExprTag.Cast && classCall.getTag() == TypedExprTag.Call,
			"class-backed unary minus did not become a carrier-preserving exact call");
		assertTrue(classResult.isRepresentationPreservingCast(), "exact static operator result lost its unchanged storage");
		assertTrue(classCall.getDeclaration() != null && classCall.getDeclaration().getSignature().getName() == "arbitraryClassNeg",
			"class-backed helper was not selected by @:op metadata");
		assertTrue(classResult.getType().getSemanticKey() == "nominal:Main.ClassNeg", "class-backed call lost its declared result type");

		final primitiveResult = initializer(main, "primitiveResult");
		final primitiveCall = primitiveResult.getExpressions()[0];
		assertTrue(primitiveResult.isRepresentationPreservingCast(), "exact instance operator result lost its unchanged storage");
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
			&& prefixChildren[0].getTag() == TypedExprTag.Block
			&& prefixChildren[1].getTag() == TypedExprTag.Cast,
			"inline prefix mutation/result schedule was not explicit");
		assertInlineStorageUpdate(prefixChildren[0], "nominal:Main.PrefixValue", 30);

		final postfixResult = initializer(main, "postfixResult");
		final postfixBlock = inlineBlock(postfixResult);
		final postfixChildren = postfixBlock.getExpressions();
		assertTrue(postfixResult.getTag() == TypedExprTag.Cast
			&& postfixBlock.getTag() == TypedExprTag.Block
			&& postfixChildren.length == 3
			&& postfixChildren[0].getTag() == TypedExprTag.Temporary
			&& postfixChildren[1].getTag() == TypedExprTag.Block
			&& postfixChildren[2].getTag() == TypedExprTag.Cast,
			"postfix result was inferred from spelling instead of the helper's saved-old-value body");
		assertInlineStorageUpdate(postfixChildren[1], "nominal:Main.PrefixValue", 1);
		assertTrue(postfixChildren[2].getExpressions()[0].getLocalBindings()[0].getIdentity().equals(postfixChildren[0].getLocalBindings()[0].getIdentity()),
			"postfix result no longer reads the helper's saved old value");

		final propertyPrefix = initializer(main, "propertyPrefix");
		assertPropertyStorageProof(propertyPrefix);
		final propertyPrefixBlock = inlineBlock(propertyPrefix);
		final propertyGetterCall = declarationExpression(propertyPrefix, "get_value");
		final propertySetterCall = declarationExpression(propertyPrefix, "set_value");
		assertTrue(propertyPrefixBlock.getTag() == TypedExprTag.Block
			&& propertyGetterCall != null
			&& propertyGetterCall.getType().getSemanticKey() == "nominal:Main.PrefixValue"
			&& propertySetterCall != null
			&& propertySetterCall.getExpressions()[1].getType().getSemanticKey() == "nominal:Main.PrefixValue"
			&& !containsDeclaration(propertyPrefix, "arbitraryPrefix")
			&& !containsTag(propertyPrefix, TypedExprTag.Unary),
			"property prefix update did not become an explicit getter/setter schedule");
		final propertyPostfix = initializer(main, "propertyPostfix");
		assertPropertyStorageProof(propertyPostfix);
		final propertyPostfixBlock = inlineBlock(propertyPostfix);
		assertTrue(propertyPostfixBlock.getTag() == TypedExprTag.Block
			&& propertyPostfixBlock.getExpressions().length == 4
			&& containsDeclaration(propertyPostfix, "get_value")
			&& containsDeclaration(propertyPostfix, "set_value")
			&& !containsDeclaration(propertyPostfix, "arbitraryPostfix")
			&& !containsTag(propertyPostfix, TypedExprTag.Unary),
			"property postfix update selected an abstract helper or lost its saved old value");

		assertTrue(initializer(main, "missingLogicalProbe").getTag() == TypedExprTag.BoolValue
			&& initializer(main, "missingLogicalProbe").getBoolValue(),
			"typeError did not capture a missing abstract logical-not operator");
		assertTrue(initializer(main, "wrongFixityProbe").getTag() == TypedExprTag.BoolValue
			&& initializer(main, "wrongFixityProbe").getBoolValue(),
			"typeError did not capture an unsupported abstract postfix fixity");
		assertTrue(initializer(main, "validProbe").getTag() == TypedExprTag.BoolValue && !initializer(main, "validProbe").getBoolValue(),
			"typeError reported a valid ordinary unary expression as invalid");
		var inferredVoidPrefix:Null<TypedExpr> = null;
		for (statement in main.getBody().getStatements())
			if (statement.getTag() == TypedStmtTag.Expression && statement.getExpressions().length == 1) {
				final expression = statement.getExpressions()[0];
				if (expression.getTag() == TypedExprTag.Block && expression.getType().isVoid())
					inferredVoidPrefix = expression;
			}
		assertTrue(inferredVoidPrefix != null
			&& !containsTag(inferredVoidPrefix, TypedExprTag.Unary)
			&& containsTag(inferredVoidPrefix, TypedExprTag.Assign),
			"unannotated inline operator did not seal its inferred Void result and explicit mutation body");
		assertInlineStorageUpdate(inferredVoidPrefix.getExpressions()[0], "nominal:Main.VoidPrefix", 1);

		final nativeBitsResult = initializer(main, "nativeBitsResult");
		final nativeBitsUnary = nativeBitsResult.getExpressions()[0];
		assertTrue(nativeBitsResult.getTag() == TypedExprTag.Cast
			&& nativeBitsResult.getType().getSemanticKey() == "nominal:Main.NativeBits"
			&& nativeBitsUnary.getTag() == TypedExprTag.Unary
			&& nativeBitsUnary.getUnaryOperator() == HxUnaryOperator.BitwiseNot
			&& nativeBitsUnary.getExpressions()[0].getType().getSemanticKey() == "primitive:Int"
			&& !containsTag(nativeBitsResult, TypedExprTag.Call),
			"bodyless abstract operator did not become an explicitly authorized primitive-carrier unary operation");
		assertTrue(nativeBitsResult.isRepresentationPreservingCast()
			&& nativeBitsUnary.getExpressions()[0].isRepresentationPreservingCast(),
			"selected bodyless operator lost the exact operand or result storage guarantee");
		final nativeStaticBitsResult = initializer(main, "nativeStaticBitsResult");
		assertTrue(nativeStaticBitsResult.getTag() == TypedExprTag.Cast
			&& nativeStaticBitsResult.getExpressions()[0].getTag() == TypedExprTag.Unary
			&& !containsTag(nativeStaticBitsResult, TypedExprTag.Call),
			"bodyless static operator was emitted as a helper call instead of its authorized carrier unary operation");
		assertTrue(nativeStaticBitsResult.isRepresentationPreservingCast()
			&& nativeStaticBitsResult.getExpressions()[0].getExpressions()[0].isRepresentationPreservingCast(),
			"selected static bodyless operator lost its storage guarantee");

		assertTrue(initializer(main, "ordinaryNumber").getTag() == TypedExprTag.Unary,
			"ordinary numeric unary behavior was routed through the abstract catalog");
		final ordinaryControl = initializer(main, "ordinaryControl");
		assertTrue(ordinaryControl.getTag() == TypedExprTag.Unary && ordinaryControl.getDeclaration() == null,
			"ordinary class acquired operator behavior from a similarly named method");
		// Haxe 4.3.7 types an increment or decrement of a nullable local as the
		// underlying number (`$type(n++)` reports Int and `var old = n++; old = null;`
		// is rejected on static targets), while a compound assignment keeps the
		// nullable destination type. Nested `Null<Null<Int>>` declarations keep their
		// written type and update like one nullable layer.
		final nullablePostfixResult = initializer(main, "nullablePostfixResult");
		final nullablePrefixResult = initializer(main, "nullablePrefixResult");
		assertTrue(nullablePostfixResult.getTag() == TypedExprTag.Unary
			&& nullablePostfixResult.getUnaryFixity() == HxUnaryFixity.Postfix
			&& nullablePostfixResult.getType().getSemanticKey() == "primitive:Int",
			"nullable postfix update did not produce the underlying Int value");
		assertTrue(nullablePrefixResult.getTag() == TypedExprTag.Unary
			&& nullablePrefixResult.getUnaryFixity() == HxUnaryFixity.Prefix
			&& nullablePrefixResult.getType().getSemanticKey() == "primitive:Int",
			"nullable prefix update did not produce the underlying Int value");
		var nullableCall:Null<TypedExpr> = null;
		for (statement in main.getBody().getStatements())
			for (expression in statement.getExpressions()) {
				final candidate = declarationExpression(expression, "shouldFail");
				if (candidate != null)
					nullableCall = candidate;
			}
		assertTrue(nullableCall != null
			&& nullableCall.getExpressions().length == 2
			&& nullableCall.getExpressions()[1].getTag() == TypedExprTag.Unary
			&& nullableCall.getExpressions()[1].getType().getSemanticKey() == "primitive:Int",
			"nullable postfix expression was not preserved through the validation call boundary");
		assertTrue(initializer(main, "nullableCompoundResult").getType().getSemanticKey() == "nullable:primitive:Int",
			"nullable compound assignment lost its nullable destination type");
		assertTrue(initializer(main, "nullableFloatPrefixResult").getType().getSemanticKey() == "primitive:Float",
			"nullable Float prefix update did not produce the underlying Float value");
		assertTrue(initializer(main, "nestedCopy").getType().getDisplay() == "Null<Null<Int>>", "nested nullable declaration did not keep its written type");
		assertTrue(initializer(main, "nestedPostfixResult").getType().getSemanticKey() == "primitive:Int",
			"nested nullable postfix update did not produce the underlying Int value");

		typingFailure([
			"abstract Missing(Int) { public inline function new(value:Int) this = value; }",
			"class Main { static function main() { var value:Missing = new Missing(1); var result = -value; } }",
		].join("\n"), "No applicable abstract unary operator");
		typingFailure([
			"class Ordinary { public function new() {} }",
			"class Main { static function main() { var value = new Ordinary(); var result = value++; } }",
		].join("\n"), "Ordinary should be Int");
		typingFailure([
			"class Main { static function main() { var value:Null<String> = null; var result = value++; } }",
		].join("\n"), "Null<String> should be Int");
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
		typingFailure([
			"abstract TextValue(String) {",
			"  public inline function new(value:String) this = value;",
			"  @:op(++A) public static function arbitrary(value:TextValue):TextValue return value;",
			"}",
			"class TextHolder {",
			"  var stored:TextValue;",
			"  public var value(get, set):TextValue;",
			"  public function new(value:String) stored = new TextValue(value);",
			"  function get_value():TextValue return stored;",
			"  function set_value(value:TextValue):TextValue return stored = value;",
			"}",
			"class Main { static function main() { var holder = new TextHolder('x'); var result = ++holder.value; } }",
		].join("\n"),
			"Abstract property increment/decrement requires an Int or Float underlying carrier");
		typingFailure([
			"abstract ReadOnlyValue(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public static function mustNotRun(value:ReadOnlyValue):ReadOnlyValue return value;",
			"}",
			"class ReadOnlyHolder {",
			"  var stored:ReadOnlyValue;",
			"  public var value(get, never):ReadOnlyValue;",
			"  public function new(value:Int) stored = new ReadOnlyValue(value);",
			"  function get_value():ReadOnlyValue return stored;",
			"}",
			"class Main { static function main() { var holder = new ReadOnlyHolder(1); var result = ++holder.value; } }",
		].join("\n"),
			"Abstract property increment/decrement requires explicit get and set accessors");
		typingFailure([
			"abstract StaticReadOnly(Int) from Int {}",
			"class StaticReadOnlyHolder {",
			"  public static var value(get, never):StaticReadOnly;",
			"  static function get_value():StaticReadOnly return 1;",
			"}",
			"class Main { static function main() { var result = ++StaticReadOnlyHolder.value; } }",
		].join("\n"),
			"Abstract property increment/decrement requires explicit get and set accessors");
		final staticModule = typedModule([
			"abstract StaticValue(Int) {",
			"  public inline function new(value:Int) this = value;",
			"  @:op(++A) public static function mustNotRun(value:StaticValue):StaticValue return value;",
			"}",
			"class StaticHolder {",
			"  static var stored:StaticValue = new StaticValue(1);",
			"  public static var value(get, set):StaticValue;",
			"  static function get_value():StaticValue return stored;",
			"  static function set_value(value:StaticValue):StaticValue return stored = value;",
			"}",
			"class Main { static function main() {",
			"  var prefixInc = ++StaticHolder.value;",
			"  var postfixInc = StaticHolder.value++;",
			"  var prefixDec = --StaticHolder.value;",
			"  var postfixDec = StaticHolder.value--;",
			"} }",
		].join("\n"), "Main.hx");
		final staticMain = mainFunction(staticModule);
		for (name in ["prefixInc", "postfixInc", "prefixDec", "postfixDec"]) {
			final result = initializer(staticMain, name);
			final getter = declarationExpression(result, "get_value");
			final setter = declarationExpression(result, "set_value");
			assertTrue(getter != null
				&& setter != null
				&& getter.getDeclaration().getIsStatic()
				&& setter.getDeclaration().getIsStatic()
				&& getter.getDeclaration().getOwner().getCanonicalName() == "Main.StaticHolder"
				&& setter.getDeclaration().getOwner().getCanonicalName() == "Main.StaticHolder"
				&& containsTag(result, TypedExprTag.Binary)
				&& !containsDeclaration(result, "mustNotRun")
				&& !containsTag(result, TypedExprTag.Unary),
				name
				+ " lost the exact static accessors or selected an abstract operator");
			final block = inlineBlock(result);
			assertTrue(block.getTag() == TypedExprTag.Block
				&& block.getExpressions().length == (StringTools.startsWith(name, "postfix") ? 3 : 1),
				name + " lost the static property update schedule");
		}

		crossModuleInlineTest();
		inlineHelperShadowingTest();
	}
}
