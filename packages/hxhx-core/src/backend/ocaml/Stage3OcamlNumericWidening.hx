package backend.ocaml;

/**
	Haxe's implicit Int-to-Float promotion at native value boundaries.

	Why
	- Haxe lets an `Int` value flow into a `Float` destination without a cast:
	  `var f:Float = 4`, `takesFloat(count)`, and `floats.put(2)` where
	  `floats:Box<Float>`. The value is promoted to Float at that boundary.
	- Native OCaml keeps `int` and `float` apart. An OCaml `int` is an
	  immediate value, while a `float` that passes through generic (`_`) code is
	  a pointer to a boxed double. If an immediate `2` reaches code that reads a
	  boxed float, the program reads memory at address `2` and crashes with
	  SIGSEGV instead of failing to compile.
	- The Stage3 emitter used to promote only Int literals and locals whose
	  parsed type text was `Int`, and only when the parameter was written as
	  `Float`. A parameter written as a type parameter `T` (instantiated with
	  Float), a call result typed Int, or an Int arithmetic expression passed
	  through unchanged.

	What
	- `needsPromotion` asks the checked types, not the source text: the value's
	  type is exactly `Int` and the destination type is exactly `Float`, after
	  typedefs are expanded. A type parameter that the typer already replaced with
	  `Float` (`Box<Float>.put(value:T)`) is a Float destination here.
	- Nullable sources and destinations (`Null<Int>`, `Null<Float>`) are not
	  handled here: `Stage3OcamlNullablePrimitive` owns that carrier and already
	  promotes inside it. Dynamic, unresolved, and open type-parameter
	  destinations are not promoted; they accept the Int value as it is.
	- `promote` wraps one rendered OCaml int expression in `float_of_int`. The
	  operand is evaluated once, in place.

	Gotchas
	- Call `promote` only on a rendering that is still an OCaml `int`. A
	  caller that already rendered the value as a float must not promote again;
	  OCaml rejects `float_of_int` of a float at compile time, so a double
	  promotion is a build error rather than a silent wrong value.
 */
function needsPromotion(actual:Null<TyType>, expected:Null<TyType>):Bool
	return isExactly(actual, "primitive:Int") && isFloatDestination(expected);

/**
	True when `expected` is exactly a non-nullable Float. Use this alone only
	where the value's own checked type is not retained, such as a field write
	whose right operand the caller has already proven to be an Int.
 */
function isFloatDestination(expected:Null<TyType>):Bool
	return isExactly(expected, "primitive:Float");

private function isExactly(type:Null<TyType>, key:String):Bool {
	if (type == null)
		return false;
	final revealed = TyAliasExpansion.reveal(type);
	return !revealed.isNullable() && revealed.getSemanticKey() == key;
}

/** Promote one rendered OCaml `int` value to `float`. */
function promote(value:String):String
	return "(float_of_int (" + value + "))";

/**
	Convert one rendered value for a non-nullable Float destination.

	- An exact `Int` value is promoted (`float_of_int`).
	- A `Null<Int>` value arrives in the nullable carrier (an `Obj.t` holding an
	  immediate int, or the null sentinel). It is unwrapped first, then
	  promoted. A `Null<Float>` value is unwrapped. A null value raises the
	  runtime's Null Access error, as for nullable arithmetic operands.
	- A `Null<Float>` destination receives the nullable Float carrier: see
	  `toNullableFloatDestination`. Null stays null there.
	- Every other value, and every non-Float destination, is returned
	  unchanged.

	Why: storing the carrier of `Null<Int>` (an immediate `3`) into a Float
	field, `Array<Float>` slot or Float return made a later Float read
	dereference address 3 and crash with SIGSEGV.
 */
function toFloatDestination(actual:Null<TyType>, expected:Null<TyType>, value:String):String {
	if (actual == null || expected == null)
		return value;
	if (Stage3OcamlNullablePrimitive.innerPrimitive(expected) == "primitive:Float")
		return toNullableFloatDestination(actual, value);
	if (!isFloatDestination(expected))
		return value;
	if (isExactly(actual, "primitive:Int"))
		return promote(value);
	return switch Stage3OcamlNullablePrimitive.innerPrimitive(actual) {
		case "primitive:Int": promote(Stage3OcamlNullablePrimitive.unwrap("primitive:Int", value));
		case "primitive:Float": "(" + Stage3OcamlNullablePrimitive.unwrap("primitive:Float", value) + ")";
		case _: value;
	};
}

/**
	A `Null<Float>` destination holds the nullable Float carrier: null, or a
	boxed Float. An Int value is promoted and boxed. A `Null<Int>` carrier
	stays null when it is null and otherwise becomes a boxed Float, so a
	later `nullable_float_unwrap` reads a real Float. A Float or `Null<Float>`
	value already has that representation.
 */
private function toNullableFloatDestination(actual:TyType, value:String):String {
	if (isExactly(actual, "primitive:Int"))
		return Stage3OcamlNullablePrimitive.box("primitive:Float", "float_of_int (" + value + ")");
	if (Stage3OcamlNullablePrimitive.innerPrimitive(actual) == "primitive:Int")
		return Stage3OcamlNullablePrimitive.nullableIntToNullableFloat(value);
	return value;
}

/** Whether `toFloatDestination` changes the value's representation. */
function convertsToFloat(actual:Null<TyType>, expected:Null<TyType>):Bool {
	if (actual == null || expected == null)
		return false;
	final inner = Stage3OcamlNullablePrimitive.innerPrimitive(actual);
	if (Stage3OcamlNullablePrimitive.innerPrimitive(expected) == "primitive:Float")
		return isExactly(actual, "primitive:Int") || inner == "primitive:Int";
	if (!isFloatDestination(expected))
		return false;
	return isExactly(actual, "primitive:Int") || inner == "primitive:Int" || inner == "primitive:Float";
}
