package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetFunctionFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionRole;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionSignature;

/**
	Copies static functions with exact primitive parameters and results.

	The body may contain the same locals, reads, and lexical blocks as the stock
	Haxe adapter. Missing or unsupported facts reject the whole function; this
	adapter never substitutes an empty body for authored behavior.
**/
class HxhxOcamlTargetFunctionAdapter {
	public static function fromFunction(owner:TyNominalInfo, fn:TypedFunction):Null<OcamlTargetFunctionFact> {
		if (owner == null || fn == null)
			throw "native OCaml target function adapter requires complete typed facts";
		final declaration = fn.getDeclaration();
		if (declaration == null
			|| !declaration.getOwner().equals(owner.getIdentity())
			|| declaration.getModulePath() != owner.getModulePath())
			return null;
		final signature = declaration.getSignature();
		final returnType = signature.getReturnType().getCanonicalDisplay();
		if (!signature.getIsStatic()
			|| !OcamlTargetFunctionFact.admitsResult(returnType)
			|| declaration.getTypeParameterIds().length != 0
			|| fn.getDefaults().length != 0)
			return null;
		final argumentTypes = [for (type in signature.getArgs()) type.getCanonicalDisplay()];
		for (index in 0...argumentTypes.length)
			if (!OcamlTargetFunctionFact.admitsValue(argumentTypes[index])
				|| signature.getArgOptional()[index]
				|| signature.getArgRest()[index])
				return null;
		fn.assertParsedBodyCurrent();
		final targetSignature:OcamlTargetFunctionSignature = {
			moduleId: owner.getModulePath(),
			sourceTypeName: owner.getShortName(),
			sourceFunctionName: signature.getName(),
			role: OcamlTargetFunctionRole.StaticFunction,
			argumentTypeDisplays: argumentTypes,
			returnTypeDisplay: returnType
		};
		final identity = OcamlTargetFunctionFact.identityFor(targetSignature);
		final nativeParameters = [
			for (parameter in TypedBodySource.functionProjection(fn).getParameters())
				parameter.getBinding()
		];
		final parameters = [
			for (index in 0...nativeParameters.length)
				HxhxOcamlTargetBindingAdapter.fromBinding(identity, nativeParameters[index],
					reflaxe.ocaml.target.OcamlTargetExpressionPath.indexed("root", "parameter", index))
		];
		final body = HxhxOcamlTargetExpressionAdapter.fromFunctionBody(identity, fn.getStableIdentity(), fn.getBody(), owner, nativeParameters, parameters,
			returnType);
		if (body == null || !body.admitsFunctionResult(returnType))
			return null;
		return new OcamlTargetFunctionFact(targetSignature, body, parameters);
	}
}
