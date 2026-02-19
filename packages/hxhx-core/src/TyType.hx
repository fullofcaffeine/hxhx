/**
	Very small type representation for Stage 3 bring-up.

	Why:
	- A “real” Haxe typer needs a rich type system (monomorphs, abstracts,
	  structural types, etc.). That’s too big to land all at once.
	- For bootstrapping, we still want a *typed* skeleton so later stages can
	  attach semantic meaning to parsed AST nodes.

	What:
	- A minimal, string-backed type descriptor (`display`) with a couple of
	  helpers for interpreting common type-hint strings.

	How:
	- This intentionally does not parse the full Haxe type grammar yet.
	- Stage 3 grows `TyType` rung-by-rung; at first we mostly normalize:
	  - primitives (`Int`, `Float`, `Bool`, `String`, `Void`)
	  - `Dynamic`
	  - unknown/unspecified type (`Unknown`)
**/
class TyType {
	public final display:String;

	function new(display:String) {
		this.display = display;
	}

	public static function unknown():TyType {
		return new TyType("Unknown");
	}

	public function isUnknown():Bool {
		return display == "Unknown";
	}

	public function isVoid():Bool {
		return display == "Void";
	}

	public function isNumeric():Bool {
		return display == "Int" || display == "Float";
	}

	public static function fromHintText(hint:String):TyType {
		if (hint == null)
			return unknown();
		final s = StringTools.trim(hint);
		if (s.length == 0)
			return unknown();
		return switch (s) {
			case "Int", "Float", "Bool", "String", "Void", "Dynamic": new TyType(s);
			case _: new TyType(s);
		}
	}

	/**
		Best-effort unification for the Stage 3 bootstrap typer.

		Why
		- Gate 1 needs failures to be “missing typer feature X”, not “we crashed”.
		- We therefore implement a small, deterministic unifier that can:
		  - refine `Unknown` to a concrete type
		  - unify numeric ops (`Int` + `Float` → `Float`)
		  - treat `Null` as compatible with most types (bootstrap simplification)

		What
		- Returns the unified type when compatible.
		- Returns `null` when incompatible (callers decide whether to error or
		  keep `Unknown`).

		How
		- This is not upstream Haxe typing. It is an incremental rung intended to
		  carry us until a real monomorph engine exists.
	**/
	public static function unify(a:TyType, b:TyType):Null<TyType> {
		if (a == null || b == null)
			return null;

		if (a.isUnknown())
			return b;
		if (b.isUnknown())
			return a;

		if (a.display == b.display)
			return a;

		// Bootstrap rule: treat `null` as compatible with most things.
		if (a.display == "Null")
			return b;
		if (b.display == "Null")
			return a;

		// Numeric widening: Int + Float (or comparisons) unify to Float.
		if (a.isNumeric() && b.isNumeric())
			return new TyType("Float");

		// Dynamic accepts anything (bootstrap).
		if (a.display == "Dynamic")
			return a;
		if (b.display == "Dynamic")
			return b;

		return null;
	}

	public function toString():String {
		return display;
	}

	/**
		Non-inline getter for `display`.

		Why
		- The OCaml backend builds with dune `-opaque`, which can make direct record
		  field access across compilation units fragile during bootstrap.
	**/
	public function getDisplay():String {
		return display;
	}
}
