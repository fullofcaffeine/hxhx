package reflaxe.ocaml.ast;

/**
	Constructs a typed invocation together with its originating function identity.

	The caller selects the invocation conversion and identity representation from
	typed plans. This module only materializes those choices. A view evaluates its
	producer once and copies the origin identity instead of identifying the newly
	allocated adapter. The native collector owns both fields and their captures;
	there is no registry that can retain abandoned callbacks.

	These operations require an admitted non-null view. They do not classify
	Dynamic values, recover nullable functions, select bound-method identity, or
	grant permission to change an exported or foreign calling convention.

	The identity type belongs to the selected representation, not to the arrow type.
**/
function carrier(invocation:OcamlTypeExpr, identity:OcamlTypeExpr):OcamlTypeExpr {
	return TTuple([invocation, identity]);
}

/** Capture one produced function before constructing its selected identity. */
function origin(value:OcamlExpr, identity:OcamlExpr->OcamlExpr, fresh:String->String):OcamlExpr {
	final name = fresh("callable_origin");
	final local:OcamlExpr = EIdent(name);
	return ELet(name, value, ETuple([local, identity(local)]), false);
}

/**
	Allocate one Haxe function identity for each evaluation of a lambda literal.

	OCaml can share a capture-free invocation closure across evaluations. Its
	physical address therefore cannot identify the Haxe lambda. A fresh mutable
	cell supplies a distinct, collector-owned token even when invocation is shared.
	Only the typed literal producer may choose this operation. Reading an existing
	function or adapting its signature must preserve the token already selected.
**/
function literal(value:OcamlExpr, fresh:String->String):OcamlExpr {
	return origin(value, _ -> EApp(EField(EIdent("Obj"), "repr"), [EApp(EIdent("ref"), [EConst(CUnit)])]), fresh);
}

/** Change invocation while retaining the exact identity of the source view. */
function adapt(value:OcamlExpr, conversion:OcamlExpr->OcamlExpr, fresh:String->String):OcamlExpr {
	final name = fresh("callable_view");
	final local:OcamlExpr = EIdent(name);
	return ELet(name, value, ETuple([conversion(invocation(local)), identity(local)]), false);
}

/** Read only from the non-null carrier selected by the caller's representation plan. */
function invocation(value:OcamlExpr):OcamlExpr {
	return EApp(EIdent("Stdlib.fst"), [value]);
}

/** Preserve the source function's identity across any number of adapted views. */
function identity(value:OcamlExpr):OcamlExpr {
	return EApp(EIdent("Stdlib.snd"), [value]);
}

/** Evaluate both operands in source order before the selected identity comparison. */
function compare(left:OcamlExpr, right:OcamlExpr, comparison:(OcamlExpr, OcamlExpr) -> OcamlExpr, fresh:String->String):OcamlExpr {
	final leftName = fresh("callable_left");
	final rightName = fresh("callable_right");
	return ELet(leftName, left, ELet(rightName, right, comparison(identity(EIdent(leftName)), identity(EIdent(rightName))), false), false);
}
