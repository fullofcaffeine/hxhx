package backend.ocaml;

/**
	Lowers a Haxe-checked explicit `String` cast to its OCaml representation.

	Haxe accepts a cast from a String-backed abstract or `Dynamic` only when the
	source program promises a String value at this point. OCaml can still know the
	input as `Obj.t`, so this boundary reinterprets that already-checked runtime
	value as `string`. Casts to all other destinations stay with the caller's
	existing lowering until their representations have separate contracts.
**/
class OcamlExplicitStringCast {
	public static function render(typeHint:String, value:String):Null<String> {
		final destination = TyType.fromHintText(typeHint);
		if (destination.getSemanticKey() != "primitive:String")
			return null;
		return "(Obj.obj (Obj.repr (" + value + ")) : string)";
	}
}
