package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierKind;

/**
	Proves a nullable nested Map comes from the target's exact lookup primitive.

	The applied getter signature returns Null<Map<K,V>>, whose mapped carrier is
	Obj.t. HxMap preserves the stored reference or returns the Haxe null sentinel.
	This admits a checked recovery by the existing closed storage-alias plan;
	it does not authorize arbitrary nullable locals, casts, or user methods.
**/
function producesObjectCarrier(expression:TypedExpr, innerMap:Type):Bool {
	if (OcamlStandardMapCarrierContract.kindForType(innerMap) == null)
		return false;
	return switch (expression.expr) {
		case TParenthesis(child), TMeta(_, child): producesObjectCarrier(child, innerMap);
		case TBlock(expressions) if (expressions.length > 0): final result = expressions[expressions.length - 1]; // Haxe stores effectful receivers and keys before the final lookup.
			// Keep the whole block as the evaluated value; inspect only its result owner.
			TypeTools.toString(result.t) == TypeTools.toString(expression.t) && producesObjectCarrier(result, innerMap);
		case TCall(callee = {expr: TField(_, FStatic(owner, field))}, arguments) if (arguments.length == 2):
			final declaration = owner.get();
			final name = OcamlTypedDeclarationIdentity.canonicalSourceName(declaration.meta, declaration.pack.concat([declaration.name]).join("."), "a class");
			if (name != "haxe.ds.NativeHxMap") {
				false;
			} else {
				final expectedKind:Null<OcamlStandardMapCarrierKind> = switch (field.get().name) {
					case "get_string": StringKeys;
					case "get_int": IntKeys;
					case "get_object": ObjectIdentityKeys;
					case _: null;
				};
				final parameters = OcamlStandardMapCarrierContract.declarationParameters(arguments[0].t);
				final signatureMatches = switch (TypeTools.follow(callee.t)) {
					case TFun(parameters, result) if (parameters.length == 2):
						TypeTools.toString(result) == TypeTools.toString(expression.t);
					case _: false;
				};
				expectedKind != null
				&& signatureMatches
				&& OcamlStandardMapCarrierContract.kindForType(arguments[0].t) == expectedKind
				&& parameters != null
				&& parameters.length > 0
				&& TypeTools.toString(TypeTools.follow(parameters[parameters.length - 1])) == TypeTools.toString(TypeTools.follow(innerMap))
				;
			}
		case _: false;
	};
}
#end
