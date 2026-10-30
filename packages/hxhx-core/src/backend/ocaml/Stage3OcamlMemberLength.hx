package backend.ocaml;

/** The two built-in receivers whose `.length` has a native runtime read. */
enum Stage3OcamlLengthReceiver {
	StringValue;
	ArrayValue;
}

/**
	Lower `x.length` on a `String` or `Array` from the typed type of `x`.

	Why
	- A Haxe string is an OCaml `string` and a Haxe array is an `HxBootArray.t`
	  (an alias of `HxArray.t`). Neither is an `HxAnon` record. The dynamic
	  lookup `HxAnon.get` only special-cases a few members of each: for an
	  array it answers `length`, `iterator`, `indexOf`, `lastIndexOf`, and
	  `slice`, and for a string `cca`, `indexOf`, `lastIndexOf`, `substr`, and
	  `substring`. It returns `null` for a string's length and for any member
	  it does not special-case. The emitter must know from typing that the
	  receiver is a String or an Array to call `HxString.length` or
	  `HxBootArray.length` directly, rather than rely on that shim.
	- The receiver can come from anywhere the typer recorded a type: a local,
	  an instance or static field (`box.text`), an index (`parts[1]`), or a
	  call result (`maybe(true)`). This module only reads the type; the emitter
	  collects it from those typed facts.

	What
	- `classify` returns the receiver kind for an exact `String`, `Array<T>`,
	  `Null<String>`, or `Null<Array<T>>` type (aliases are revealed first), and
	  `null` for every other type, including `Dynamic`, anonymous structures,
	  and abstracts over `String`.
	- `lower` renders the read. A nullable receiver is bound once and tested
	  first: a null value raises the runtime's `Null Access` exception, the same
	  catchable value that unwrapping a null `Null<Int>` raises. Upstream Haxe
	  also throws a catchable error for `null.length`; calling `String.length`
	  on the OCaml null value would instead crash the process.

	Gotcha
	- A receiver typed as plain `String` or `Array<T>` is read directly, without
	  a null test, like every other native String/Array read. Only receivers
	  whose type admits null pay for the check.
 */
function classify(type:Null<TyType>):Null<Stage3OcamlLengthReceiver> {
	if (type == null)
		return null;
	final concrete = TyAliasExpansion.revealNonNullable(type);
	if (concrete.getSemanticKey() == "primitive:String")
		return StringValue;
	final identity = concrete.getNominalIdentity();
	if (identity != null && identity.getCanonicalName() == "Array" && concrete.getTypeArguments().length == 1)
		return ArrayValue;
	return null;
}

/** Whether a value of this exact type may be null at run time by its declared type. */
function admitsNull(type:TyType):Bool
	return TyAliasExpansion.reveal(type).isNullable();

/** Render `.length` for a classified receiver; returns null when `type` is not a String or Array. */
function lower(type:Null<TyType>, receiver:String, quote:String->String):Null<String> {
	final kind = classify(type);
	if (kind == null)
		return null;
	final read = switch kind {
		case StringValue: "HxString.length";
		case ArrayValue: "HxBootArray.length";
	};
	if (!admitsNull(type))
		return read + " (" + receiver + ")";
	// The receiver is evaluated before the binding is in scope, so this name
	// cannot capture a user value of the same spelling.
	return "(let __hx_length_receiver = ("
		+ receiver
		+ ") in if HxRuntime.is_null (Obj.repr __hx_length_receiver) then HxRuntime.hx_throw_typed (Obj.repr "
		+ quote("Null Access")
		+ ") [\"String\"; \"Dynamic\"] else "
		+ read
		+ " (__hx_length_receiver))";
}

/**
	Stop emission when a member read on a typed String or Array receiver would
	fall back to a dynamic record lookup.

	Why
	- `HxAnon.get` returns `null` for a string's length and for any member the
	  runtime shim does not special-case, so the program would run and print a
	  wrong value instead of failing. A named emit-time error points at the
	  unsupported shape instead. On a typed receiver, `.length` is lowered
	  before this point, and in the current Stage3 tests no other member read
	  on a typed String or Array receiver reaches this lookup.

	What
	- Throws when `type` is a String or Array (or `Null<...>` of one). Any other
	  receiver type, including an unknown one, returns without effect, so
	  `Dynamic` and structural receivers keep their dynamic lookup.
 */
function rejectDynamicLookup(type:Null<TyType>, field:String):Void {
	final kind = classify(type);
	if (kind == null)
		return;
	final receiver = switch kind {
		case StringValue: "String";
		case ArrayValue: "Array";
	};
	throw "stage3 emitter: member `"
		+ field
		+ "` on a "
		+ receiver
		+ " receiver has no native lowering; a dynamic field lookup would return null";
}
