package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;

/**
	Recovers a concrete function from nullable storage immediately before invocation.
	The caller captures the function and evaluates its arguments before this check.
	Checking closure and infix tags prevents invoking a null sentinel as native code.
	The supplied signature comes from the typed core Null<function> declaration.
**/
function recover(value:OcamlExpr, signature:OcamlTypeExpr, fresh:String->String):OcamlExpr {
	final name = fresh("nullable_callee");
	final local = OcamlExpr.EIdent(name);
	final tag = OcamlExpr.EApp(OcamlExpr.EIdent("Obj.tag"), [local]);
	final callable = OcamlExpr.EBinop(OcamlBinop.And, OcamlExpr.EApp(OcamlExpr.EIdent("Obj.is_block"), [local]),
		OcamlExpr.EBinop(OcamlBinop.Or, OcamlExpr.EBinop(OcamlBinop.Eq, tag, OcamlExpr.EIdent("Obj.closure_tag")),
			OcamlExpr.EBinop(OcamlBinop.Eq, tag, OcamlExpr.EIdent("Obj.infix_tag"))));
	final typed = OcamlExpr.EAnnot(OcamlExpr.EApp(OcamlExpr.EIdent("Obj.obj"), [local]), signature);
	return OcamlExpr.ELet(name, value,
		OcamlExpr.EIf(callable, typed, OcamlExpr.EApp(OcamlExpr.EIdent("invalid_arg"), [OcamlExpr.EConst(OcamlConst.CString("Cannot call null"))])), false);
}

/**
	Captures one callback before argument effects can replace its storage.
	Arguments are evaluated in source order. A null callback raises only after
	those effects, matching Haxe invocation order. Each expression executes once.
**/
function call(value:OcamlExpr, arguments:Array<OcamlExpr>, signature:OcamlTypeExpr, fresh:String->String):OcamlExpr {
	final callee = fresh("nullable_function");
	final bindings:Array<{name:String, value:OcamlExpr}> = [{name: callee, value: value}];
	final values:Array<OcamlExpr> = [];
	for (argument in arguments) {
		final name = fresh("nullable_argument");
		bindings.push({name: name, value: argument});
		values.push(OcamlExpr.EIdent(name));
	}
	var result = OcamlExpr.EApp(recover(OcamlExpr.EIdent(callee), signature, fresh), values);
	for (index in 0...bindings.length) {
		final binding = bindings[bindings.length - 1 - index];
		result = OcamlExpr.ELet(binding.name, binding.value, result, false);
	}
	return result;
}
#end
