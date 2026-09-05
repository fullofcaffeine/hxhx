package backend.ocaml;

import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact;
import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact.OcamlTargetFieldInitializerRole;
import reflaxe.ocaml.target.OcamlTargetFieldInitializerFact.OcamlTargetFieldInitializerSignature;

/** Copies one admitted native typed field initializer into target-owned facts. **/
class HxhxOcamlTargetFieldInitializerAdapter {
	public static function fromInitializer(owner:TyNominalInfo, initializer:TypedFieldInitializer):Null<OcamlTargetFieldInitializerFact> {
		if (owner == null || initializer == null)
			throw "native OCaml target field adapter requires complete typed facts";
		final field = initializer.getField();
		if (!field.getOwner().equals(owner.getIdentity()) || field.getModulePath() != owner.getModulePath() || !field.getIsStatic())
			return null;
		final typeDisplay = field.getType().getCanonicalDisplay();
		if (typeDisplay != "Int" && typeDisplay != "Bool" && typeDisplay != "String")
			return null;
		final signature:OcamlTargetFieldInitializerSignature = {
			moduleId: owner.getModulePath(),
			sourceTypeName: owner.getShortName(),
			sourceFieldName: field.getName(),
			role: OcamlTargetFieldInitializerRole.StaticField,
			semanticTypeDisplay: typeDisplay
		};
		final targetExpression = HxhxOcamlTargetExpressionAdapter.fromExpression(OcamlTargetFieldInitializerFact.identityFor(signature),
			initializer.getExpression());
		return targetExpression == null
			|| targetExpression.semanticTypeDisplay != typeDisplay ? null : new OcamlTargetFieldInitializerFact(signature, targetExpression);
	}
}
