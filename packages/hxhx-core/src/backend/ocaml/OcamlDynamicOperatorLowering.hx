package backend.ocaml;

/** The source value shape that enters a declared `Dynamic` call parameter. */
enum OcamlDynamicArgumentCarrier {
	/** A Boolean needs the runtime box that keeps it distinct from an OCaml integer. */
	ExactBool;

	/** The expression already produces the reviewed `Obj.t` Dynamic carrier. */
	DynamicValue;

	/** Another concrete value needs one ordinary `Obj.repr` conversion. */
	ConcreteValue;
}

/**
	Builds the target code for native Stage3 Dynamic boundaries.

	A Haxe `Dynamic` value uses `Obj.t` in generated OCaml. Boolean values need a
	distinct runtime box because OCaml represents `true` and integer `1` with the
	same immediate bits. The emitter selects each conversion from Haxe type facts.
	The runtime then checks the value category before it applies a unary operator.
**/
class OcamlDynamicOperatorLowering {
	/** Returns true when a parsed type hint names the Dynamic carrier. */
	public static function isDynamicTypeHint(typeHint:String):Bool {
		final compact = StringTools.replace(StringTools.trim(typeHint == null ? "" : typeHint), " ", "");
		return compact == "Dynamic" || compact == "Std.Any" || compact == "Any";
	}

	/** Returns the concrete OCaml carrier for Dynamic, or `null` for another type. */
	public static function carrierType(type:TyType):Null<String> {
		return type != null && isDynamicTypeHint(type.toString()) ? "Obj.t" : null;
	}

	/**
		Converts one source argument to a declared Dynamic parameter.

		The caller supplies the value shape from typed Stage3 facts. This function
		does not inspect generated text or guess the value category at runtime.
	**/
	public static function callArgument(typeHint:String, carrier:OcamlDynamicArgumentCarrier, renderedValue:String):String {
		if (!isDynamicTypeHint(typeHint))
			return renderedValue;
		return switch (carrier) {
			case ExactBool: "HxRuntime.box_bool (" + renderedValue + ")";
			case DynamicValue: renderedValue;
			case ConcreteValue: "Obj.repr (" + renderedValue + ")";
		};
	}

	/**
		Returns a checked runtime call for one Dynamic unary expression.

		The result stays in `Obj.t`. This keeps switch branches and Dynamic returns
		monomorphic after logical-not, numeric negation, and bitwise complement use
		different primitive representations.
	**/
	public static function unary(op:HxUnaryOperator, operandIsDynamic:Bool, renderedOperand:String):Null<String> {
		if (!operandIsDynamic)
			return null;
		final operation = switch (op) {
			case LogicalNot: "logicalNot";
			case Negate: "negate";
			case BitwiseNot: "bitwiseNot";
			case Increment, Decrement: null;
		};
		return operation == null ? null : "HxDynamic." + operation + " (Obj.repr (" + renderedOperand + "))";
	}

	/**
		Returns a checked runtime expression for one binary operation with a Dynamic operand.

		OCaml's `&&` and `||` operators keep the right operand lazy. Other operations
		materialize each operand once when the selected runtime function receives it.
	**/
	public static function binary(op:String, leftCarrier:OcamlDynamicArgumentCarrier, rightCarrier:OcamlDynamicArgumentCarrier, leftIsDynamic:Bool,
			rightIsDynamic:Bool, renderedLeft:String, renderedRight:String):Null<String> {
		if (!leftIsDynamic && !rightIsDynamic)
			return null;
		final left = callArgument("Dynamic", leftCarrier, renderedLeft);
		final right = callArgument("Dynamic", rightCarrier, renderedRight);
		return switch (op) {
			case "==": "HxRuntime.dynamic_equals (" + left + ") (" + right + ")";
			case "!=": "not (HxRuntime.dynamic_equals (" + left + ") (" + right + "))";
			case "&&": "((HxDynamic.booleanValue (" + left + ")) && (HxDynamic.booleanValue (" + right + ")))";
			case "||": "((HxDynamic.booleanValue (" + left + ")) || (HxDynamic.booleanValue (" + right + ")))";
			case "+": runtimeBinary("add", left, right);
			case "-": runtimeBinary("subtract", left, right);
			case "*": runtimeBinary("multiply", left, right);
			case "/": runtimeBinary("divide", left, right);
			case "%": runtimeBinary("remainder", left, right);
			case "<": runtimeBinary("lessThan", left, right);
			case "<=": runtimeBinary("lessThanOrEqual", left, right);
			case ">": runtimeBinary("greaterThan", left, right);
			case ">=": runtimeBinary("greaterThanOrEqual", left, right);
			case "&": runtimeBinary("bitwiseAnd", left, right);
			case "|": runtimeBinary("bitwiseOr", left, right);
			case "^": runtimeBinary("bitwiseXor", left, right);
			case "<<": runtimeBinary("shiftLeft", left, right);
			case ">>": runtimeBinary("shiftRight", left, right);
			case ">>>": runtimeBinary("unsignedShiftRight", left, right);
			case _:
				null;
		};
	}

	static function runtimeBinary(operation:String, left:String, right:String):String {
		return "HxDynamic." + operation + " (" + left + ") (" + right + ")";
	}
}
