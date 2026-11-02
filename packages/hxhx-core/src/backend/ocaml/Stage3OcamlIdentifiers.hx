package backend.ocaml;

/**
	OCaml spellings for Haxe names that OCaml reserves.

	Haxe allows some names that OCaml cannot use as a value identifier:
	- `_` is an ordinary, readable Haxe name (`static var _ = 11;`,
	  `catch (_:String) trace(_)`), but OCaml `_` is a wildcard pattern.
	- OCaml keywords, including the infix operator keywords `land`, `lor`,
	  `lxor`, `lsl`, `lsr`, and `asr`, are valid Haxe names (`var land = 8;`).

	Stage3 maps `_` to `UNDERSCORE` and adds `_` after a keyword.
**/
class Stage3OcamlIdentifiers {
	/** The OCaml name for a Haxe value, field, or local named `_`. The leading underscore keeps OCaml's unused-variable warning quiet. */
	public static inline final UNDERSCORE = "_hx_underscore";

	/** Whether `name` is reserved by OCaml and cannot be a value identifier as written. */
	public static function isKeyword(name:String):Bool {
		if (name == null)
			return false;
		return switch (name) {
			case "and" | "as" | "assert" | "asr" | "begin" | "class" | "constraint" | "do" | "done" | "downto" | "effect" | "else" | "end" | "exception" |
				"external" | "false" | "for" | "fun" | "function" | "functor" | "if" | "in" | "include" | "inherit" | "initializer" | "land" | "lazy" |
				"let" | "lor" | "lsl" | "lsr" | "lxor" | "match" | "method" | "module" | "mutable" | "mod" | "new" | "nonrec" | "object" | "of" | "open" |
				"or" | "private" | "rec" | "sig" | "struct" | "then" | "to" | "true" | "try" | "type" | "val" | "virtual" | "when" | "while" | "with":
				true;
			case _:
				false;
		}
	}
}
