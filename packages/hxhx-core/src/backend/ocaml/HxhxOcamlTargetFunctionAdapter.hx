package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionPath;
import reflaxe.ocaml.target.OcamlTargetFunctionFact;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionRole;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionSignature;

/** Copies the first admitted native function body into target-owned facts. **/
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
		final statements = fn.getBody().getStatements();
		if (statements.length != 0)
			return null;
		final targetSignature:OcamlTargetFunctionSignature = {
			moduleId: owner.getModulePath(),
			sourceTypeName: owner.getShortName(),
			sourceFunctionName: signature.getName(),
			role: OcamlTargetFunctionRole.StaticFunction,
			argumentTypeDisplays: [],
			returnTypeDisplay: "Void"
		};
		final body = OcamlTargetExpressionFact.block(OcamlTargetExpressionPath.ROOT, "Void", []);
		return new OcamlTargetFunctionFact(targetSignature, body);
	}
}
