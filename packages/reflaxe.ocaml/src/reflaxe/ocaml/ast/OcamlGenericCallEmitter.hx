package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.require as genericCallRequire;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.OcamlGenericInstanceCallTarget;

/**
	Materializes already-selected generic conversions without reinterpreting Haxe types.

	Inputs are locals bound by the caller in source order. Callback adapters capture
	these produced function values outside the invocation body, so ignoring or
	repeating a callback cannot drop or repeat its producer's effects. The returned
	expression contains only runtime identifiers owned by this conversion plan.
**/
function emit(target:OcamlGenericInstanceCallTarget, method:OcamlExpr, receiver:OcamlExpr, arguments:Array<OcamlExpr>, fresh:String->String,
		runtime:(String, String) -> OcamlExpr):OcamlExpr {
	genericCallRequire(target);
	if (arguments.length != target.arguments.length)
		throw "reflaxe.ocaml [ocaml-generic-call:invalid-syntax]: incorrect materialized argument count";
	final bindings:Array<{name:String, value:OcamlExpr}> = [];
	final converted:Array<OcamlExpr> = [receiver];
	for (index in 0...arguments.length) {
		final name = fresh("generic_argument");
		bindings.push({name: name, value: convert(target.arguments[index], arguments[index], 'generic-call:argument:$index', fresh, runtime)});
		converted.push(EIdent(name));
	}
	if (arguments.length == 0)
		converted.push(EConst(CUnit));
	final result = fresh("generic_result");
	var output:OcamlExpr = ELet(result, EApp(method, converted), convert(target.result, EIdent(result), "generic-call:result", fresh, runtime), false);
	var index = bindings.length;
	while (index-- > 0)
		output = ELet(bindings[index].name, bindings[index].value, output, false);
	return output;
}

private function convert(conversion:OcamlGenericValueConversion, value:OcamlExpr, role:String, fresh:String->String,
		runtime:(String, String) -> OcamlExpr):OcamlExpr {
	return switch (conversion) {
		case Identity: value;
		case BoxValue: EApp(EField(EIdent("Obj"), "repr"), [value]);
		case UnboxValue: EApp(EField(EIdent("Obj"), "obj"), [value]);
		case BoxBoolean: EApp(runtime(role, "HxRuntime.box_bool"), [value]);
		case UnboxBoolean: EApp(runtime(role, "HxRuntime.unbox_bool_or_obj"), [value]);
		case BoxNullableBoolean, UnboxNullableBoolean:
			// A nullable Bool stores a raw bool; erased T stores a tagged Bool.
			// Bind callback results once before checking and converting their value.
			final name = fresh("generic_nullable_bool");
			final input:OcamlExpr = EIdent(name);
			final converted:OcamlExpr = conversion == BoxNullableBoolean ? EApp(runtime('$role/value', "HxRuntime.box_bool"),
				[EApp(EField(EIdent("Obj"), "obj"),
					[input])]) : EApp(EField(EIdent("Obj"), "repr"), [EApp(runtime('$role/value', "HxRuntime.unbox_bool_or_obj"), [input])]);
			ELet(name, value, EIf(EBinop(PhysEq, input, runtime('$role/null', "HxRuntime.hx_null")), input, converted), false);
		case AdaptFunction(arguments, result):
			final callback = fresh("generic_callback");
			final patterns:Array<OcamlPat> = [];
			final inputs:Array<OcamlExpr> = [];
			for (index in 0...arguments.length) {
				final name = fresh("generic_input");
				patterns.push(PVar(name));
				inputs.push(convert(arguments[index], EIdent(name), '$role/argument:$index', fresh, runtime));
			}
			if (arguments.length == 0) {
				patterns.push(PConst(CUnit));
				inputs.push(EConst(CUnit));
			}
			final invocation:OcamlExpr = EApp(EIdent(callback), inputs);
			ELet(callback, value, EFun(patterns, convert(result, invocation, '$role/result', fresh, runtime)), false);
	}
}
#end
