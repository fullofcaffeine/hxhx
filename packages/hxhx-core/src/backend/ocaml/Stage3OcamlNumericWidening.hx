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
