package backend.ocaml;

/**
	Adapt a lowered range temporary to OCaml's integer loop carrier.
	The shared bound remains Dynamic when authored that way. Only a checked
	integer payload may enter the native loop; other categories raise a Haxe
	exception instead of interpreting boxed data as an OCaml integer.
 */
function adapt(expression:HxExpr, value:String, locals:Null<TypedBackendLocalCatalog>, names:Null<Stage3OcamlLocalNames>):String {
	final local = switch expression {
		case EIdent(name): locals == null ? null : locals.findByProjectedName(name);
		case _: null;
	};
	if (local == null || !local.getBinding().getType().isDynamic())
		return value;
	if (names == null)
		throw "OCaml Dynamic range bound requires its local-name owner";
	final selected = names.internalName("__hx_range_bound");
	return "(let "
		+ selected
		+ " = ("
		+ value
		+ ") in if Obj.is_int "
		+ selected
		+ " && not (HxRuntime.is_null "
		+ selected
		+ ") then (Obj.obj "
		+ selected
		+ " : int) else HxRuntime.hx_throw_typed (Obj.repr \"Invalid Dynamic range bound; expected Int\") [\"String\"; \"Dynamic\"])";
}
