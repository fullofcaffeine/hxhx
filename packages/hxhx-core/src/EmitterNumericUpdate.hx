/** The native number representation that an increment or decrement steps. */
enum EmitterNumericUpdateKind {
	/** Haxe `Int`, stepped with the wrapping OCaml `int` helpers. */
	IntStep;

	/** Haxe `Float`, stepped with OCaml float arithmetic. */
	FloatStep;

	/** `haxe.Int64`, stepped with the repo-owned Int64 helper module. */
	Int64Step;
}

/**
	Chooses the native arithmetic used for a mutable numeric local update.

	Stage3 represents ordinary Haxe `Int` values with the OCaml `int` helpers,
	`Float` values with OCaml floats, and `haxe.Int64` values with the repo-owned
	Int64 helper module. A `Null<Int>` or `Null<Float>` local is stored in the
	nullable carrier (see `backend.ocaml.Stage3OcamlNullablePrimitive`), so its
	update reads the number through the checked unwrap and boxes the next number
	before storing it. Keeping these target spellings outside `EmitterStage`
	prevents a small representation choice from renumbering thousands of
	generated temporaries in that large module.
**/
class EmitterNumericUpdate {
	/**
		Recognize the two source spellings used to seed an unannotated Int64 local.

		The parser stores `haxe.Int64` as nested field access (`haxe` then `Int64`),
		not as one identifier containing a dot. This is a bounded bootstrap bridge for
		the existing initializer-based local-hint pass. It deliberately does not make
		all expression typing recognize an Int64 merely from its source spelling;
		declaration-scoped semantic local types are tracked by haxe_ocaml-i7d5a.
	**/
	public static function isStandardInt64Provider(owner:HxExpr):Bool {
		return switch (owner) {
			case EIdent("Int64") | EField(EIdent("haxe"), "Int64"): true;
			case _: false;
		};
	}

	/** Return the add/sub helper for the selected numeric representation. */
	public static function operation(kind:EmitterNumericUpdateKind, increment:Bool):String {
		return switch kind {
			case IntStep: increment ? "HxInt.add" : "HxInt.sub";
			case FloatStep: increment ? "( +. )" : "( -. )";
			case Int64Step: increment ? "Haxe_Int64.add" : "Haxe_Int64.sub";
		};
	}

	/** Return the value one in the selected numeric representation. */
	public static function one(kind:EmitterNumericUpdateKind):String {
		return switch kind {
			case IntStep: "1";
			case FloatStep: "1.0";
			case Int64Step: "(Haxe_Int64.ofInt (1))";
		};
	}

	/**
		Render `ident++`, `++ident`, `ident--`, or `--ident` for a local stored in
		the OCaml ref `ident`.

		The stored value is read once. When `carrier` names a nullable primitive
		(`primitive:Int` or `primitive:Float`), that read goes through the checked
		unwrap, so a null raises Null Access before anything is stored, and the
		next number is boxed back into the carrier. The expression's value is the
		plain number: the old one for postfix and the new one for prefix, matching
		Haxe's `Int` or `Float` type for the update.
	**/
	public static function local(input:{
		ident:String,
		kind:EmitterNumericUpdateKind,
		increment:Bool,
		postfix:Bool,
		?carrier:String
	}):String {
		final read = "(!" + input.ident + ")";
		final old = input.carrier == null ? read : backend.ocaml.Stage3OcamlNullablePrimitive.unwrap(input.carrier, read);
		final stored = input.carrier == null ? "__hx_next" : backend.ocaml.Stage3OcamlNullablePrimitive.box(input.carrier, "__hx_next");
		return "(let __hx_old = " + old + " in let __hx_next = " + operation(input.kind, input.increment) + " __hx_old " + one(input.kind) + " in ("
			+ input.ident + " := " + stored + "; " + (input.postfix ? "__hx_old" : "__hx_next") + "))";
	}
}
