package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;

/**
	Materializes one sealed nominal class carrier at an OCaml syntax boundary.

	The representation registry stores a canonical module-qualified identity.
	OCaml syntax cannot qualify a type with its own module while that module is
	being defined, so this helper is the sole owner of local versus qualified
	spelling.
**/
class OcamlMonomorphicClassMaterializer {
	/** Returns whether a representation is an admitted nominal class carrier. */
	public static function isNominalClass(decision:OcamlRepresentationDecision):Bool {
		return decision.boxingPolicy == OcamlRepresentationBoxingPolicy.NullableNominalRecordCarrier;
	}

	/** Renders the nominal type relative to the module constructing syntax. */
	public static function typeExpr(decision:OcamlRepresentationDecision, currentTargetModuleName:String):OcamlTypeExpr {
		if (!isNominalClass(decision)
			|| decision.nominalTargetModuleName == null
			|| decision.nominalTargetTypeName == null
			|| decision.nominalLayoutRevision == null) {
			throw 'reflaxe.ocaml [ocaml-representation:invalid-nominal-materialization]: ${decision.id} is not a complete nominal class decision';
		}
		final rendered = decision.nominalTargetModuleName == currentTargetModuleName ? decision.nominalTargetTypeName : decision.nominalTargetModuleName
			+ "."
			+ decision.nominalTargetTypeName;
		return OcamlTypeExpr.TIdent(rendered);
	}
}
#end
