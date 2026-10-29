package backend.ocaml;

/** The value representation a local compound assignment computes in. */
enum Stage3OcamlLocalCompoundKind {
	/** Haxe `Int` (or the number inside a `Null<Int>` carrier), using the wrapping `HxInt` helpers. */
	IntUpdate;

	/** Haxe `Float` (or the number inside a `Null<Float>` carrier), using OCaml float arithmetic. */
	FloatUpdate;

	/** Haxe `String`, using OCaml string concatenation. Only `+=` is valid Haxe. */
	StringUpdate;
}

/**
	Emit a local compound assignment, such as `x -= 2`, as an OCaml expression
	that stores the update and produces it.

	Why: in Haxe a compound assignment is an expression. `var r = (x -= 2)` and
	`while ((i += 1) < 3)` need the stored value, so emitting the update only as a
	unit statement leaves no value for the surrounding expression. A statement
	`x -= 2;` uses this same form with its value ignored, so both positions share
	one evaluation order.

	What the emitted expression guarantees, matching Haxe 4.3.7:

	- The old value is read before the right operand runs. `y += (y += 5)` with
	  `y = 10` adds 15 to the old 10, so both `y` and the result are 25.
	- The right operand runs exactly once, and before a null old value is
	  unwrapped. A null `Null<Int>` or `Null<Float>` local raises the runtime Null
	  Access exception after the right operand ran, and nothing is stored.
	- The result is typed like the local. For a `Null<Int>` or `Null<Float>`
	  local the produced value is the same boxed carrier that was stored; for
	  `Int`, `Float`, and `String` it is the plain value.

	How: the old value and the right operand are bound in source order through
	`Stage3OcamlNullablePrimitive.orderedArithmetic`, which also unwraps a
	nullable side after both ran. The computed value is bound once, boxed when the
	local uses the nullable carrier, stored in the local's `ref`, and returned.

	This module chooses no operand conversions. The caller renders `right` in the
	local's representation (for example widening an `Int` operand of a `Float`
	update to float, or stringifying a non-String operand of `+=`) and reports a
	nullable right carrier through `rightCarrier`. Bitwise compound operators and
	abstract operator overloads are not handled here and fail at emit time.
 */
/** Arithmetic compound operators with a local value form. The six bitwise ones are not lowered yet (haxe_ocaml-sq6ii). */
function isArithmeticOperator(op:String):Bool {
	return switch op {
		case "+=" | "-=" | "*=" | "/=" | "%=": true;
		case _: false;
	};
}

/**
	The representation a local of exact type `type` updates in: `Int` or
	`Float` (also inside a nullable carrier) or `String`. Null for every other
	type, including `Dynamic`, which keeps its own runtime operation.
 */
function kindOf(type:TyType):Null<Stage3OcamlLocalCompoundKind> {
	final carrier = Stage3OcamlNullablePrimitive.innerPrimitive(type);
	return switch carrier != null ? carrier : TyAliasExpansion.reveal(type).getSemanticKey() {
		case "primitive:Int": IntUpdate;
		case "primitive:Float": FloatUpdate;
		case "primitive:String": StringUpdate;
		case _: null;
	};
}

/** Whether a local of exact type `type` has a compound value form: a `kindOf` kind or `Dynamic`. */
function hasValueForm(type:TyType):Bool {
	return type.isDynamic() || kindOf(type) != null;
}

function value(input:{
	ident:String,
	op:String,
	kind:Stage3OcamlLocalCompoundKind,
	carrier:Null<String>,
	old:String,
	right:String,
	rightCarrier:Null<String>,
	names:Stage3OcamlLocalNames
}):String {
	if (input.names == null)
		throw "OCaml local compound assignment value requires a local naming owner";
	final operation = arithmetic(input.kind, input.op);
	final next = Stage3OcamlNullablePrimitive.orderedArithmetic({
		left: input.old,
		leftInner: input.carrier,
		right: input.right,
		rightInner: input.rightCarrier,
		asFloat: input.kind == FloatUpdate,
		names: input.names,
		body: operation
	});
	return store(input.ident, next, input.carrier, input.names);
}

/**
	Store an already computed next value in the local `ref` and produce it.
	A nullable carrier boxes the plain number once, so the stored and produced
	values are the same box. Other values are stored and produced unchanged,
	which is also how a Dynamic local's computed carrier is kept.
 */
function store(ident:String, next:String, carrier:Null<String>, names:Stage3OcamlLocalNames):String {
	final bound = names.internalName("__hx_compound_value");
	final stored = carrier == null ? "(" + next + ")" : Stage3OcamlNullablePrimitive.box(carrier, next);
	return "(let " + bound + " = " + stored + " in (" + ident + " := " + bound + "; " + bound + "))";
}

function arithmetic(kind:Stage3OcamlLocalCompoundKind, op:String):(String, String) -> String {
	return switch [kind, op] {
		case [IntUpdate, "+="]: (left, right) -> "(HxInt.add (" + left + ") (" + right + "))";
		case [IntUpdate, "-="]: (left, right) -> "(HxInt.sub (" + left + ") (" + right + "))";
		case [IntUpdate, "*="]: (left, right) -> "(HxInt.mul (" + left + ") (" + right + "))";
		case [IntUpdate, "%="]: (left, right) -> "(HxInt.rem (" + left + ") (" + right + "))";
		case [FloatUpdate, "+="]: (left, right) -> "((" + left + ") +. (" + right + "))";
		case [FloatUpdate, "-="]: (left, right) -> "((" + left + ") -. (" + right + "))";
		case [FloatUpdate, "*="]: (left, right) -> "((" + left + ") *. (" + right + "))";
		case [FloatUpdate, "/="]: (left, right) -> "((" + left + ") /. (" + right + "))";
		case [FloatUpdate, "%="]: (left, right) -> "(mod_float (" + left + ") (" + right + "))";
		case [StringUpdate, "+="]: (left, right) -> "((" + left + ") ^ (" + right + "))";
		case _: throw "unsupported OCaml local compound assignment value: " + op + " on " + kind.getName();
	};
}
