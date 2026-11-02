package backend.ocaml;

/**
	The value of a Stage3 static field that has no initializer.

	Haxe gives such a field its type's default: `0`, `0.0` or `false` for a
	non-null Int, Float or Bool, and `null` for every other type (String,
	nullable primitives, classes, arrays, anonymous structures, functions and
	Dynamic). Stage3 used to emit `(Obj.magic 0)` for all of them. For a String
	that is the immediate `0`, not the runtime null sentinel, so a null check
	such as `HxString.toStdString` did not recognize it and the program crashed
	when it printed the field.

	A field whose type typing did not resolve keeps the old polymorphic
	`(Obj.magic 0)`: there is no checked type to choose a representation from.
**/
function value(type:Null<TyType>):String {
	if (type == null || type.isUnknown() || type.isUnresolved())
		return "(Obj.magic 0)";
	if (type.isNullable())
		return "(Obj.magic HxRuntime.hx_null)";
	return switch TyAliasExpansion.reveal(type).getSemanticKey() {
		case "primitive:Int": "0";
		case "primitive:Float": "0.";
		case "primitive:Bool": "false";
		case _: "(Obj.magic HxRuntime.hx_null)";
	};
}
