package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;

/** Mechanical OCaml syntax facts derived from one validated String decision. */
typedef OcamlStringRepresentationMaterialization = {
	final carrierType:OcamlTypeExpr;
	final implicitDefault:OcamlExpr;
}

/**
	Materializes the exact core String carrier and its Haxe null default.

	The registry owns the semantic decision and names the sole runtime boundary:
	`HxString.hx_null_string`, whose runtime module constructs the canonical
	String-carrier sentinel once. This helper validates that complete proof
	before constructing a reference to that value. It never emits a fresh unsafe
	cast, inspects a Haxe type, chooses a fallback, or handles native boundaries.
**/
class OcamlStringRepresentationMaterializer {
	static inline final PROOF_ID = "nullable-string-runtime-sentinel-carrier-v1";

	/** Validates and materializes one admitted exact String storage domain. */
	public static function materialize(decision:OcamlRepresentationDecision,
			expectedDomain:OcamlRepresentationDomain):OcamlStringRepresentationMaterialization {
		switch (expectedDomain) {
			case InternalValue, MutableLocalStorage, CapturedLocalStorage, InstanceField, StaticField:
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-string-representation:unsupported-domain]: exact String materialization does not admit $expectedDomain';
		}
		if (decision.domain != expectedDomain) {
			throw 'reflaxe.ocaml [ocaml-string-representation:wrong-domain]: representation ${decision.id} selects ${decision.domain}, but materialization requires $expectedDomain';
		}
		if (decision.semanticTypeId != "String"
			|| decision.carrierTypeId != "string"
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.NullableStringCarrier
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel
			|| decision.proof.id != PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-string-representation:unsupported-decision]: representation ${decision.id} must select exact String -> string with runtime-sentinel null, nullable-string carrier, runtime-null default, and proof $PROOF_ID';
		}
		return {
			carrierType: OcamlTypeExpr.TIdent("string"),
			implicitDefault: OcamlExpr.EField(OcamlExpr.EIdent("HxString"), "hx_null_string")
		};
	}
}
#end
