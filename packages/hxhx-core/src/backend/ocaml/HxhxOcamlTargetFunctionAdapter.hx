package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetFunctionFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionRole;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionSignature;

/**
	Copies static zero-argument Void functions into the shared target contract.

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
		if (!signature.getIsStatic() || signature.getArgs().length != 0 || signature.getReturnType().getCanonicalDisplay() != "Void")
			return null;
		fn.assertParsedBodyCurrent();
		final targetSignature:OcamlTargetFunctionSignature = {
			moduleId: owner.getModulePath(),
			sourceTypeName: owner.getShortName(),
			sourceFunctionName: signature.getName(),
			role: OcamlTargetFunctionRole.StaticFunction,
			argumentTypeDisplays: [],
			returnTypeDisplay: "Void"
		};
		final body = HxhxOcamlTargetExpressionAdapter.fromFunctionBody(OcamlTargetFunctionFact.identityFor(targetSignature), fn.getStableIdentity(),
			fn.getBody(), owner);
		if (body == null || body.semanticTypeDisplay != "Void")
			return null;
		return new OcamlTargetFunctionFact(targetSignature, body);
	}
}
