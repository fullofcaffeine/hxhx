package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;

/** Mechanical OCaml syntax facts derived from one validated field decision. */
typedef OcamlFieldRepresentationMaterialization = {
	final carrierType:OcamlTypeExpr;
	final implicitDefault:OcamlExpr;
}

/**
	Materializes field syntax from a program-owned representation decision.

	The registry decides the semantic type, carrier, storage domain, and Haxe
	implicit default. This helper checks that complete decision and translates it
	to the small OCaml AST fragments used by record and static-cell declarations.
	It never inspects a Haxe type or selects a fallback representation.
**/
class OcamlFieldRepresentationMaterializer {
	/**
		Returns the direct exact-Int field carrier and implicit zero initializer.

		Other semantic families stay rejected until their field representation and
		default policies receive their own bounded proof.
	**/
	public static function materializeExactInt(decision:OcamlRepresentationDecision,
			expectedDomain:OcamlRepresentationDomain):OcamlFieldRepresentationMaterialization {
		switch (expectedDomain) {
			case InstanceField, StaticField:
			case InternalValue, MutableLocalStorage, CapturedLocalStorage, ArrayElement:
				throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-domain]: field materialization requires instance-field or static-field, not $expectedDomain';
		}
		if (decision.domain != expectedDomain) {
			throw 'reflaxe.ocaml [ocaml-field-representation:wrong-domain]: representation ${decision.id} selects ${decision.domain}, but field materialization requires $expectedDomain';
		}
		if (decision.semanticTypeId != "Int"
			|| decision.carrierTypeId != "int"
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.ExactIntZero) {
			throw 'reflaxe.ocaml [ocaml-field-representation:unsupported-decision]: representation ${decision.id} must select exact Int -> int with exact-int-zero, but selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} with ${decision.implicitDefaultPolicy}';
		}
		return {
			carrierType: OcamlTypeExpr.TIdent("int"),
			implicitDefault: OcamlExpr.EConst(OcamlConst.CInt(0))
		};
	}
}
#end
