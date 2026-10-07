import TyAssignmentCompatibility.TyAssignmentNullPolicy;

/** Directional assignment contracts independently observed with upstream typed call operands. */
class M14AssignmentCompatibilityTest {
	static function check(expected:TyType, actual:TyType, policy:TyAssignmentNullPolicy, wanted:TyCallArgumentCompatibility):Void {
		final result = TyAssignmentCompatibility.classify(expected, actual, policy);
		if (result != wanted)
			throw actual.getCanonicalDisplay() + " -> " + expected.getCanonicalDisplay() + ": expected " + wanted + ", got " + result;
	}

	static function main():Void {
		unnamedOptionalSignatures();
		bindingOwnership();
		spreadAssignments();
		functionAssignments();
		genericAssignments();
		dynamicErasure();
		final cases:Array<{expected:String, actual:String, wanted:TyCallArgumentCompatibility}> = [
			{expected: "Float", actual: "Int", wanted: Compatible},
			{expected: "Int", actual: "Float", wanted: Incompatible},
			{expected: "Int", actual: "String", wanted: Incompatible},
			{expected: "Int", actual: "Bool", wanted: Incompatible},
			{expected: "Int", actual: "Dynamic", wanted: Compatible},
			{expected: "Dynamic", actual: "Int", wanted: Compatible},
			{expected: "Int", actual: "Null<Int>", wanted: Compatible},
			{expected: "Float", actual: "Null<Int>", wanted: Compatible},
			{expected: "Int", actual: "Null<Float>", wanted: Incompatible},
			{expected: "Null<Int>", actual: "Int", wanted: Compatible}
		];
		for (entry in cases)
			check(TyType.fromHintText(entry.expected), TyType.fromHintText(entry.actual), Unchecked, entry.wanted);
		check(TyType.fromHintText("Int"), TyType.fromHintText("Null<Int>"), Strict, Incompatible);
		check(TyType.fromHintText("Null<Int>"), TyType.fromHintText("Int"), Strict, Compatible);
		check(TyType.fromHintText("Int"), TyType.fromHintText("Dynamic"), Strict, Compatible);
		check(TyType.fromHintText("Dynamic"), TyType.fromHintText("Null<Int>"), Strict, Compatible);
		check(TyType.fromHintText("Int"), TyType.fromHintText("Null"), Unchecked, Compatible);
		check(TyType.fromHintText("Int"), TyType.fromHintText("Null"), Strict, Incompatible);
		check(TyType.fromHintText("Null<Int>"), TyType.fromHintText("Null"), Strict, Compatible);
		check(TyType.fromHintText("Dynamic"), TyType.unknown(), Unchecked, Unknown);
		for (type in [
			TyType.unknown(),
			TyType.fromHintText("Missing"),
			TyType.functionType([TyType.unknown()], TyType.fromHintText("Int")),
			TyType.anonymous(["value"], [TyType.unknown()])
		])
			check(type, type, Unchecked, Unknown);
		final named = TyType.nominal(new TyNominalTypeId("model.Value"), []);
		check(named, named, Strict, Compatible);
		check(TyType.nominal(new TyNominalTypeId("model.Other"), [], "Float"), TyType.fromHintText("Int"), Unchecked, Unknown);
		final parameters = TyType.fromHintText("(?label:String,value:Int)->Int").getFunctionParameters();
		final aligned = TyCallAlignment.align(parameters, [Value],
			(_, parameter, _) -> TyAssignmentCompatibility.classify(parameters[parameter].type, TyType.fromHintText("Int"), Unchecked));
		switch (aligned) {
			case Aligned([Omitted, Supplied(0)]):
			case _:
				throw "directional compatibility did not drive optional argument alignment";
		}
		Sys.println("ASSIGNMENT_COMPATIBILITY:PASS");
	}

	/** Dynamic receives known values without promising their unresolved inner inference types. */
	static function dynamicErasure():Void {
		final dynamicType = TyType.fromHintText("Dynamic");
		final unknown = TyType.unknown();
		final record = TyType.anonymous(["value"], [unknown]);
		for (value in [
			record,
			TyType.functionType([record], TyType.fromHintText("Void")),
			TyType.nominal(new TyNominalTypeId("Array"), [unknown])
		]) {
			check(dynamicType, value, Unchecked, Compatible);
			check(value, value, Unchecked, Unknown);
		}
		for (value in [
			unknown,
			TyType.fromHintText("Missing"),
			TyType.anonymous(["value"], [TyType.fromHintText("Missing")]),
			TyType.functionType([TyType.fromHintText("Missing")], dynamicType),
			TyType.nominal(new TyNominalTypeId("Array"), [TyType.fromHintText("Missing")])
		])
			check(dynamicType, value, Unchecked, Unknown);
		check(dynamicType, TyType.fromHintText("Void"), Unchecked, Incompatible);
	}

	/** Generic Dynamic is directional and never erases unknown or unrelated nominal identity. */
	static function genericAssignments():Void {
		final integer = TyType.fromHintText("Int");
		final floating = TyType.fromHintText("Float");
		final dynamicType = TyType.fromHintText("Dynamic");
		function box(type:TyType):TyType
			return TyType.nominal(new TyNominalTypeId("model.Box"), [type]);
		check(box(dynamicType), box(integer), Unchecked, Compatible);
		check(box(integer), box(dynamicType), Unchecked, Incompatible);
		check(box(floating), box(integer), Unchecked, Incompatible);
		check(box(box(dynamicType)), box(box(integer)), Unchecked, Compatible);
		check(box(box(integer)), box(box(dynamicType)), Unchecked, Incompatible);
		check(box(dynamicType), box(TyType.unknown()), Unchecked, Unknown);
		check(box(dynamicType), TyType.nominal(new TyNominalTypeId("other.Box"), [integer]), Unchecked, Unknown);
		check(box(dynamicType), TyType.nominal(new TyNominalTypeId("model.Box"), [integer, integer]), Unchecked, Unknown);
		check(box(dynamicType), TyType.fromHintText("Box<Int>"), Unchecked, Unknown);
	}

	/** Optionality belongs to a parameter even when its type hint has no parameter label. */
	static function unnamedOptionalSignatures():Void {
		for (hint in ["(?Int)->Int", "(? Int)->Int", "(?value:Int)->Int"]) {
			final parameter = TyType.fromHintText(hint).getFunctionParameters()[0];
			if (!parameter.isOptional || parameter.type.getSemanticKey() != TyType.fromHintText("Int").getSemanticKey())
				throw "optional hint lost parameter facts: " + hint;
		}
		final optionalNullable = TyType.fromHintText("(?Null<Int>)->Int").getFunctionParameters()[0];
		final requiredNullable = TyType.fromHintText("(Null<Int>)->Int").getFunctionParameters()[0];
		if (!optionalNullable.isOptional || !optionalNullable.type.isNullable() || requiredNullable.isOptional || !requiredNullable.type.isNullable())
			throw "optional and nullable parameter facts were conflated";
		final optional = TyCallableSignature.fromFunctionValue(TyType.fromHintText("(?Int)->Int"));
		if (!TyCallValidation.validate(optional, [], [], Unchecked).match(Aligned([Omitted])))
			throw "unnamed optional parameter cannot be omitted";
		final required = TyCallableSignature.fromFunctionValue(TyType.fromHintText("(Null<Int>)->Int"));
		if (!TyCallValidation.validate(required, [], [], Unchecked).match(Rejected(MissingRequired(0))))
			throw "required nullable parameter became omittable";
	}

	/** Typed calls retain immutable argument facts and reject rewrites that invalidate them. */
	static function bindingOwnership():Void {
		final integer = TyType.fromHintText("Int");
		final functionType = TyType.fromHintText("(?label:String,value:Int)->Int");
		final callee = TypedExpr.nameRead("callback", functionType, null);
		final operand = TypedExpr.intLiteral(7, integer, null);
		final operands = [operand];
		final call = TypedExpr.functionValueCall(callee, operands, integer, null);
		operands.pop();
		final binding = call.getArgumentBinding();
		if (binding == null || call.getExpressions().length != 2 || call.getExpressions()[1] != operand)
			throw "bound call changed or lost its original source children";
		binding.getSlots().pop();
		binding.getOperandTypes().pop();
		if (binding.getSlots().length != 2 || binding.getOperandTypes().length != 1)
			throw "binding getter exposed mutable storage";
		switch (binding.getSlots()) {
			case [Omitted, Supplied(0)]:
			case _:
				throw "binding lost the skipped interior parameter";
		}
		final rewritten = call.withExpressions([callee, TypedExpr.intLiteral(8, integer, null)]);
		if (rewritten.getArgumentBinding() != binding)
			throw "type-preserving rewrite discarded the argument binding";
		rejectBinding(() -> {
			call.withExpressions([callee]);
		});
		rejectBinding(() -> {
			call.withExpressions([callee, TypedExpr.stringLiteral("bad", TyType.fromHintText("String"), null)]);
		});
		rejectBinding(() -> {
			call.withType(TyType.fromHintText("Float"));
		});
		rejectBinding(() -> {
			binding.assertCurrent(functionType, [integer], [Spread]);
		});
		rejectBinding(() -> {
			call.withExpressions([
				TypedExpr.nameRead("other", TyType.fromHintText("(value:Float)->Int"), null),
				operand
			]);
		});
		final legacy = TypedExpr.call(callee, [operand], null, integer, null);
		if (CompilerTypedTreeRevision.expression("test", legacy) == CompilerTypedTreeRevision.expression("test", call))
			throw "typed revision ignored the argument binding";
		final optional = TypedExpr.nameRead("optional", TyType.fromHintText("(?value:Int)->Int"), null);
		final omitted = TypedExpr.functionValueCall(optional, [], integer, null);
		final suppliedNull = TypedExpr.functionValueCall(optional, [TypedExpr.nullValue(TyType.fromHintText("Null"), null)], integer, null);
		if (omitted.getArgumentBinding().getSemanticKey() == suppliedNull.getArgumentBinding().getSemanticKey())
			throw "binding revision merged omission and explicit null";
		final rest = TypedExpr.nameRead("rest", TyType.fromHintText("(...values:Int)->Int"), null);
		final restCall = TypedExpr.functionValueCall(rest, [operand, operand], integer, null);
		switch (restCall.getArgumentBinding().getSlots()[0]) {
			case RestElements(indices):
				indices.pop();
			case _:
				throw "missing rest membership";
		}
		switch (restCall.getArgumentBinding().getSlots()[0]) {
			case RestElements([0, 1]):
			case _:
				throw "binding exposed mutable rest membership";
		}
		Sys.println("CALL_ARGUMENT_BINDING:PASS");
	}

	static function rejectBinding(action:() -> Void):Void {
		try {
			action();
		} catch (error:String) {
			return;
		}
		throw "invalid call binding rewrite was accepted";
	}

	/** A spread supplies one container, whose element type cannot use ordinary numeric widening. */
	static function spreadAssignments():Void {
		final integer = TyType.fromHintText("Int");
		final floating = TyType.fromHintText("Float");
		final dynamicType = TyType.fromHintText("Dynamic");
		final cases:Array<{expected:TyType, actual:TyType, wanted:TyCallArgumentCompatibility}> = [
			{expected: integer, actual: TyType.nominal(new TyNominalTypeId("Array"), [integer]), wanted: Compatible},
			{expected: floating, actual: TyType.nominal(new TyNominalTypeId("Array"), [integer]), wanted: Incompatible},
			{expected: integer, actual: TyType.nominal(new TyNominalTypeId("Array"), [floating]), wanted: Incompatible},
			{expected: integer, actual: TyType.nominal(new TyNominalTypeId("Array"), [dynamicType]), wanted: Incompatible},
			{expected: integer, actual: TyType.nominal(new TyNominalTypeId("haxe.Rest"), [integer]), wanted: Compatible},
			{expected: floating, actual: TyType.nominal(new TyNominalTypeId("haxe.Rest"), [integer]), wanted: Incompatible},
			{expected: integer, actual: dynamicType, wanted: Compatible},
			{expected: integer, actual: integer, wanted: Incompatible},
			{expected: integer, actual: TyType.nominal(new TyNominalTypeId("custom.Container"), [integer], "Array"), wanted: Unknown},
			{expected: integer, actual: TyType.nominal(new TyNominalTypeId("Array"), [TyType.unknown()]), wanted: Unknown}
		];
		for (entry in cases) {
			final result = TyAssignmentCompatibility.classifyRestSpread(entry.expected, entry.actual);
			if (result != entry.wanted)
				throw "spread " + entry.actual.getCanonicalDisplay() + " into " + entry.expected.getCanonicalDisplay() + ": " + result;
		}
	}

	/** Function parameter direction differs from result direction; rest elements remain invariant. */
	static function functionAssignments():Void {
		final cases:Array<{expected:String, actual:String, wanted:TyCallArgumentCompatibility}> = [
			{expected: "(x:Int)->Int", actual: "(x:Float)->Int", wanted: Compatible},
			{expected: "(x:Float)->Int", actual: "(x:Int)->Int", wanted: Incompatible},
			{expected: "()->Float", actual: "()->Int", wanted: Compatible},
			{expected: "()->Int", actual: "()->Float", wanted: Incompatible},
			{expected: "()->Void", actual: "()->Int", wanted: Compatible},
			{expected: "()->Int", actual: "()->Void", wanted: Incompatible},
			{expected: "(x:Int)->Int", actual: "(?x:Int)->Int", wanted: Compatible},
			{expected: "(?x:Int)->Int", actual: "(x:Int)->Int", wanted: Incompatible},
			{expected: "(x:Int)->Int", actual: "(x:Int,?y:String)->Int", wanted: Incompatible},
			{expected: "(x:Int,y:String)->Int", actual: "(x:Int)->Int", wanted: Incompatible},
			{expected: "(x:Int)->Int", actual: "(...x:Int)->Int", wanted: Incompatible},
			{expected: "(...x:Int)->Int", actual: "(x:Int)->Int", wanted: Incompatible},
			{expected: "(...x:Int)->Int", actual: "(...x:Float)->Int", wanted: Incompatible},
			{expected: "(...x:Float)->Int", actual: "(...x:Int)->Int", wanted: Incompatible}
		];
		for (entry in cases)
			check(TyType.fromHintText(entry.expected), TyType.fromHintText(entry.actual), Unchecked, entry.wanted);
		final left = TyType.nominal(new TyNominalTypeId("model.Left"), []);
		final right = TyType.nominal(new TyNominalTypeId("model.Right"), []);
		final integer = TyType.fromHintText("Int");
		final voidType = TyType.fromHintText("Void");
		check(TyType.functionType([left], integer), TyType.functionType([right], integer), Unchecked, Unknown);
		check(TyType.functionType([], left), TyType.functionType([], right), Unchecked, Unknown);
		check(TyType.functionType([left], voidType), TyType.functionType([right], integer), Unchecked, Unknown);
		check(TyType.functionType([], voidType), TyType.functionType([], TyType.unknown()), Unchecked, Unknown);
	}
}
