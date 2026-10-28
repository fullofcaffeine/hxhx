package backend.ocaml;

/**
	One native representation for `Null<Int>`, `Null<Float>`, and `Null<Bool>`.

	OCaml `int`, `float`, and `bool` cannot hold a null sentinel, so a nullable
	primitive is carried as `Obj.t`: `HxRuntime.hx_null` for null, otherwise the
	same box that Dynamic uses for that primitive (`Obj.repr` for numbers,
	`HxRuntime.box_bool` for Booleans). `Std.parseInt`, the `null` literal, and
	Dynamic values already produce this carrier, so they enter a nullable
	destination unchanged. A concrete primitive is boxed on entry, and a nullable
	value is unwrapped through the checked runtime helpers before a concrete
	destination or native arithmetic reads it. Unwrapping a null raises the
	runtime's Null Access exception; upstream targets disagree about null
	arithmetic, so that exception is the documented native contract.

	Equality compares two carrier values structurally after boxing the concrete
	side, so `nullable == null` and `nullable == 42` keep Haxe's value semantics
	without unwrapping and without raising on null. Ordered comparisons are not
	converted here. Representation changes this module does not describe fail at
	emit time instead of leaving the choice to OCaml inference.
 */
final INT = "primitive:Int";

final FLOAT = "primitive:Float";
final BOOL = "primitive:Bool";

/** Return the inner primitive key when the exact type is a nullable Int, Float, or Bool. */
function innerPrimitive(type:Null<TyType>):Null<String> {
	if (type == null)
		return null;
	final revealed = TyAliasExpansion.reveal(type);
	if (!revealed.isNullable())
		return null;
	final key = TyAliasExpansion.reveal(revealed.unwrapNull()).getSemanticKey();
	return key == INT || key == FLOAT || key == BOOL ? key : null;
}

/** Return the inner key only for the numeric carriers that native arithmetic can unwrap. */
function numericInner(type:Null<TyType>):Null<String> {
	final inner = innerPrimitive(type);
	return inner == INT || inner == FLOAT ? inner : null;
}

/** Box one concrete primitive value into the carrier. The operand occurs once. */
function box(inner:String, value:String):String {
	return switch inner {
		case "primitive:Bool": "HxRuntime.box_bool (" + value + ")";
		case "primitive:Int" | "primitive:Float": "Obj.repr (" + value + ")";
		case _: throw "unsupported nullable primitive carrier: " + inner;
	};
}

/** Read the primitive out of the carrier; a null value raises the runtime Null Access exception. */
function unwrap(inner:String, value:String):String {
	return switch inner {
		case "primitive:Int": "HxRuntime.nullable_int_unwrap (" + value + ")";
		case "primitive:Float": "HxRuntime.nullable_float_unwrap (" + value + ")";
		case "primitive:Bool": "HxRuntime.nullable_bool_unwrap (" + value + ")";
		case _: throw "unsupported nullable primitive carrier: " + inner;
	};
}

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
