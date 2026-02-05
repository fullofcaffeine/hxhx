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

	public static function fromHintText(hint:String):TyType {
		if (hint == null) return unknown();
		final s = StringTools.trim(hint);
		if (s.length == 0) return unknown();
		return switch (s) {
			case "Int", "Float", "Bool", "String", "Void", "Dynamic": new TyType(s);
			case _: new TyType(s);
		}
	}

	public function toString():String {
		return display;
	}
}

