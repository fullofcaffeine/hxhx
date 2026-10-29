package backend.ocaml;

/**
	One native representation for `Null<Int>` and `Null<Float>`.

	OCaml `int` and `float` cannot hold a null sentinel, so a nullable primitive
	is carried as `Obj.t`: `HxRuntime.hx_null` for null, otherwise the same box
	that Dynamic uses for that primitive (`Obj.repr`). `Null<Bool>` is not
	converted here; its conditions still read the raw value and a separate task
	owns its carrier. `Std.parseInt`, the `null` literal, and Dynamic values
	already produce this carrier, so they enter a nullable destination unchanged.
	A concrete primitive is boxed on entry, and a nullable value is unwrapped
	through the checked runtime helpers before a concrete destination, native
	arithmetic, an ordered comparison, or an array index reads it. Unwrapping a
	null raises the runtime's Null Access exception; upstream targets disagree
	about null arithmetic, so that exception is the documented native contract.

	Equality compares two carrier values structurally after boxing the concrete
	side, so `nullable == null` and `nullable == 42` keep Haxe's value semantics
	without unwrapping and without raising on null. The handwritten String and
	Array intrinsics declare optional Int slots as `int` and test the sentinel
	bits first; `intrinsicOptionalInt` reinterprets the carrier for exactly those
	slots. Representation changes this module does not describe fail at emit
	time instead of leaving the choice to OCaml inference.
 */
final INT = "primitive:Int";

final FLOAT = "primitive:Float";

/**
	Return the inner primitive key when the exact type is a nullable Int or Float.
	Nested wrappers such as `Null<Null<Int>>` hold the same values as one layer
	(a number or null), so they share the one-layer carrier.
 */
function innerPrimitive(type:Null<TyType>):Null<String> {
	if (type == null)
		return null;
	final revealed = TyAliasExpansion.reveal(type);
	if (!revealed.isNullable())
		return null;
	final key = TyAliasExpansion.revealNonNullable(revealed).getSemanticKey();
	return key == INT || key == FLOAT ? key : null;
}

/** The numeric carriers that native arithmetic can unwrap; currently every carrier this module owns. */
function numericInner(type:Null<TyType>):Null<String>
	return innerPrimitive(type);

/**
	Box one concrete primitive value into the carrier. The operand occurs once
	and is ascribed its OCaml type, so a value rendered with the wrong
	representation is a compile-time error rather than a corrupt box.
 */
function box(inner:String, value:String):String {
	return switch inner {
		case "primitive:Int": "Obj.repr ((" + value + " : int))";
		case "primitive:Float": "Obj.repr ((" + value + " : float))";
		case _: throw "unsupported nullable primitive carrier: " + inner;
	};
}

/** Read the primitive out of the carrier; a null value raises the runtime Null Access exception. */
function unwrap(inner:String, value:String):String {
	return switch inner {
		case "primitive:Int": "HxRuntime.nullable_int_unwrap (" + value + ")";
		case "primitive:Float": "HxRuntime.nullable_float_unwrap (" + value + ")";
		case _: throw "unsupported nullable primitive carrier: " + inner;
	};
}

/**
	Evaluate both arithmetic operands, in Haxe's left-to-right order, before a
	nullable operand is unwrapped. Haxe runs both operands before the arithmetic
	reads a null, so `n + side()` and `n += side()` with a null `n` still call
	`side()` and only then raise Null Access. `left` and `right` are rendered
	operands (the carrier for a nullable side); `leftInner` and `rightInner` name
	the carrier of each nullable side or are null. `body` receives the readable
	operands: a nullable side is unwrapped (and widened to float when `asFloat`
	and the carrier holds an Int); a concrete side is passed by its bound name.
 */
function orderedArithmetic(input:{
	left:String,
	leftInner:Null<String>,
	right:String,
	rightInner:Null<String>,
	asFloat:Bool,
	names:Stage3OcamlLocalNames,
	body:(String, String) -> String
}):String {
	if (input.names == null)
		throw "ordered nullable arithmetic requires a local naming owner";
	final left = input.names.internalName("__hx_arith_left");
	final right = input.names.internalName("__hx_arith_right");
	function readable(inner:Null<String>, bound:String):String {
		if (inner == null)
			return bound;
		final value = unwrap(inner, bound);
		return input.asFloat && inner == INT ? "float_of_int (" + value + ")" : value;
	}
	return "(let "
		+ left
		+ " = ("
		+ input.left
		+ ") in let "
		+ right
		+ " = ("
		+ input.right
		+ ") in "
		+ input.body(readable(input.leftInner, left), readable(input.rightInner, right))
		+ ")";
}

/**
	Pass a nullable Int carrier into a handwritten runtime intrinsic slot that
	is declared `int` but checks `HxRuntime.is_null (Obj.repr i)` before any
	integer use (HxString.indexOf and friends). The carrier's bits are exactly
	that ABI: an immediate int or the sentinel pointer, so nothing is unwrapped
	and a null still selects the intrinsic's default.
 */
function intrinsicOptionalInt(value:String):String
	return "(Obj.obj (" + value + ") : int)";

/** Convert a value of the exact `type` into a concrete Int when it is a nullable Int; other types pass through. */
function intValue(type:Null<TyType>, value:String):String
	return innerPrimitive(type) == INT ? unwrap(INT, value) : value;

/**
	Convert a value of the exact `source` type into a nullable destination whose
	inner primitive is `inner`. Values that already use the carrier pass through.
	A missing typing fact keeps the producer's carrier, as the storage boundary
	did before nullable destinations were converted; a known foreign type fails.
 */
function store(source:TyType, inner:String, value:String):String {
	final revealed = TyAliasExpansion.reveal(source);
	if (revealed.isNullLiteral() || revealed.isDynamic() || innerPrimitive(revealed) == inner)
		return value;
	if (revealed.isUnknown() || revealed.isUnresolved() || revealed.isTypeParameter())
		return value;
	final key = revealed.getSemanticKey();
	if (key == inner)
		return box(inner, value);
	if (inner == FLOAT && key == INT)
		return box(inner, "float_of_int (" + value + ")");
	throw "unsupported OCaml nullable storage: " + key + " into nullable " + inner;
}

/** Convert a carrier value with inner primitive `inner` into the exact concrete `destination` type. */
function load(inner:String, destination:TyType, value:String):String {
	final revealed = TyAliasExpansion.reveal(destination);
	if (revealed.isDynamic() || innerPrimitive(revealed) == inner)
		return value;
	final key = revealed.getSemanticKey();
	if (key == inner)
		return unwrap(inner, value);
	if (inner == INT && key == FLOAT)
		return "float_of_int (" + unwrap(inner, value) + ")";
	throw "unsupported OCaml nullable extraction: nullable " + inner + " into " + key;
}

/**
	Render `==`/`!=` when at least one operand is a nullable primitive. Both
	sides end up in the carrier, so structural equality compares null with null,
	numbers by value, and boxed Booleans by their payload. Returns null when
	neither operand is a nullable primitive; mixed shapes this contract does not
	cover (such as a nullable Int against a concrete Float) fail at emit time.
 */
function equality(facts:TypedBackendEqualityOccurrence, left:String, right:String):Null<String> {
	final leftInner = innerPrimitive(facts.leftType);
	final rightInner = innerPrimitive(facts.rightType);
	if (leftInner == null && rightInner == null)
		return null;
	final leftCarrier = leftInner != null ? left : carrierOperand(rightInner, facts.leftType, left);
	final rightCarrier = rightInner != null ? right : carrierOperand(leftInner, facts.rightType, right);
	if (leftInner != null && rightInner != null && leftInner != rightInner)
		throw "unsupported OCaml nullable equality: " + leftInner + " against " + rightInner;
	return "((" + leftCarrier + ") " + (facts.equal ? "=" : "<>") + " (" + rightCarrier + "))";
}

/**
	Bring the concrete side of an equality into the other side's carrier. A null
	literal, a Dynamic value, or an operand without a typing fact already uses
	the carrier, as at the storage boundary.
 */
private function carrierOperand(inner:String, type:TyType, value:String):String {
	final revealed = TyAliasExpansion.reveal(type);
	if (revealed.isNullLiteral()
		|| revealed.isDynamic()
		|| revealed.isUnknown()
		|| revealed.isUnresolved()
		|| revealed.isTypeParameter())
		return value;
	final key = revealed.getSemanticKey();
	if (key == inner)
		return box(inner, value);
	if (inner == FLOAT && key == INT)
		return box(inner, "float_of_int (" + value + ")");
	throw "unsupported OCaml nullable equality: " + key + " against nullable " + inner;
}

/**
	Return the carrier's inner key for a call destination. A written nullable
	type and an optional Int, Float, or Bool parameter both receive the carrier:
	an omitted optional argument arrives as the null sentinel, so the native
	parameter must be able to hold it. Returns null for other destinations.
 */
function destinationCarrier(expected:Null<TyType>, expectedIsOptional:Bool):Null<String> {
	if (expected == null)
		return null;
	final written = innerPrimitive(expected);
	if (written != null)
		return written;
	if (!expectedIsOptional)
		return null;
	final key = TyAliasExpansion.reveal(expected).getSemanticKey();
	return key == INT || key == FLOAT ? key : null;
}

/** The checked call-argument form of destinationCarrier. */
function carrierDestination(argument:Null<TypedBackendCallArgument>):Null<String> {
	return argument == null ? null : destinationCarrier(argument.expectedType, argument.expectedIsOptional);
}

/** True when the argument crosses the nullable boundary in either direction. */
function isCarrierBoundary(argument:Null<TypedBackendCallArgument>):Bool {
	return argument != null && (innerPrimitive(argument.type) != null || carrierDestination(argument) != null);
}

/**
	Convert one checked call argument across the nullable boundary: a concrete
	primitive passed to a carrier destination is boxed, and a nullable value
	passed to a concrete primitive parameter is unwrapped. Returns null when the
	argument has no typing facts, when neither side uses the carrier, or when
	the parameter type is still open (a type parameter, Dynamic, or an
	unresolved type) and therefore accepts the carrier as it is. The caller
	passes the plain rendering, not one already coerced for a Float parameter.
 */
function callArgument(argument:Null<TypedBackendCallArgument>, rendered:String):Null<String> {
	if (argument == null || argument.type == null || argument.expectedType == null)
		return null;
	return convertArgument(argument.type, argument.expectedType, argument.expectedIsOptional, rendered);
}

/** The same conversion from explicit operand and parameter facts, as a constructor application supplies them. */
function convertArgument(actual:TyType, expected:TyType, expectedIsOptional:Bool, rendered:String):Null<String> {
	final actualInner = innerPrimitive(actual);
	final expectedInner = destinationCarrier(expected, expectedIsOptional);
	if (actualInner == null && expectedInner == null)
		return null;
	final revealed = TyAliasExpansion.reveal(expected);
	if (revealed.isDynamic() || revealed.isUnknown() || revealed.isUnresolved() || revealed.isTypeParameter())
		return null;
	if (expectedInner != null)
		return store(actual, expectedInner, rendered);
	return load(actualInner, expected, rendered);
}

/**
	Read an optional primitive parameter with a concrete default on entry. The
	caller passes the carrier (callArgument boxes it), so a present value must be
	unwrapped into the concrete body binding; a null sentinel selects the default.
 */
function parameterEntry(bindingType:TyType, name:String, fallback:String):String {
	final key = TyAliasExpansion.reveal(bindingType).getSemanticKey();
	final present = key == INT || key == FLOAT ? unwrap(key, name) : name;
	return "(if HxRuntime.is_null (Obj.repr " + name + ") then (" + fallback + ") else " + present + ")";
}

/** True when a concrete-default parameter's native annotation must be the carrier rather than its body primitive. */
function isCarrierParameter(bindingType:TyType):Bool {
	final key = TyAliasExpansion.reveal(bindingType).getSemanticKey();
	return key == INT || key == FLOAT;
}
