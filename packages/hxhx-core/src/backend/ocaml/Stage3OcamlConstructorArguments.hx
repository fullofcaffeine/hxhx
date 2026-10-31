package backend.ocaml;

/**
	The operands of one native constructor call, aligned to the selected constructor.

	`new Point(x, y)` evaluates `x` and then `y` exactly once, binds each value
	to a fresh local, and passes those locals in the declared parameter order.
	An omitted optional parameter receives the runtime null, a rest parameter
	receives an array of its elements, and an operand for an optional parameter
	(question mark or concrete default) is rendered as the nullable carrier that
	the constructor unwraps on entry.

	Class construction and abstract construction share this so both call their
	`new_` function with the same argument layout. The caller still chooses the
	callee and what surrounds the call.
**/
class Stage3OcamlConstructorArguments {
	/** One rendered OCaml argument per declared constructor parameter, in declaration order. */
	public final parameters:Array<String>;

	final locals:Array<String>;
	final rendered:Array<String>;

	/**
		`constructor` is the exact projected `new` method the occurrence selected.
		`emitArgument` renders one source operand for its checked parameter type.
	**/
	public function new(input:{
		occurrence:TypedBackendConstructorOccurrence,
		constructor:TypedBackendFunctionProjection,
		names:Stage3OcamlLocalNames,
		emitArgument:(expression:HxExpr, actual:TyType, expected:TyType, expectedIsOptional:Bool) -> String
	}) {
		final binding = input.occurrence.requireArgumentBinding();
		final slots = binding.getSlots();
		if (slots.length != input.constructor.getParameters().length)
			throw "native constructor parameter projection changed its checked arity";
		final arguments = values(input.occurrence);
		final actual = binding.getOperandTypes();
		final expected = binding.getExpectedArguments();
		// An optional parameter (question mark or concrete default) receives the
		// nullable carrier; map each supplied operand back to its declared parameter.
		final declaredArguments = HxFunctionDecl.getArgs(input.constructor.getDeclaration());
		final optionalForOperand = [for (_ in arguments) false];
		for (slot in 0...slots.length)
			switch slots[slot] {
				case Supplied(index) if (slot < declaredArguments.length):
					final declared = declaredArguments[slot];
					optionalForOperand[index] = HxFunctionArg.getIsOptional(declared)
						|| HxFunctionArg.getDefaultValue(declared).match(Default(_));
				case _:
			}
		locals = [
			for (index in 0...arguments.length)
				input.names.internalName("__hx_ctor_arg_" + index)
		];
		rendered = [
			for (index in 0...arguments.length)
				input.emitArgument(arguments[index], actual[index], expected[index], optionalForOperand[index])
		];
		parameters = [
			for (slot in slots)
				switch slot {
					case Supplied(index):
						locals[index];
					case Omitted:
						"(Obj.magic HxRuntime.hx_null)";
					case RestElements(indices):
						"HxBootArray.of_list [" + indices.map(index -> locals[index]).join("; ") + "]";
					case RestSpread(index):
						locals[index];
				}
		];
	}

	/** A checked spread passes its original array value, not the source-only spread marker. */
	public static function values(occurrence:TypedBackendConstructorOccurrence):Array<HxExpr> {
		final arguments = occurrence.getArguments();
		final kinds = occurrence.requireArgumentBinding().getOperandKinds();
		return [
			for (index in 0...arguments.length)
				if (kinds[index] == Spread) switch arguments[index] {
					case ECall(EIdent("__hxhx_spread"), [value]):
						value;
					case _:
						throw "native constructor spread lost its original array operand";
				} else arguments[index]
		];
	}

	/** Evaluate every operand in source order, then run `body`, which uses `parameters`. */
	public function evaluateBefore(body:String):String {
		var result = body;
		var index = locals.length;
		while (index-- > 0)
			result = "let " + locals[index] + " = (" + rendered[index] + ") in " + result;
		return result;
	}
}
