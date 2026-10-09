package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/** A lowered function keeps its runtime dependencies beside its checked syntax. **/
typedef OcamlTargetLoweredFunction = {
	final expression:OcamlExpr;
	final runtimeRequirements:Array<OcamlRuntimeRequirement>;
}

/** Lowers the first complete shared-target function family into OCaml syntax. **/
class OcamlTargetFunctionLowerer {
	public static function lower(fact:OcamlTargetFunctionFact, profile:String, ?finalOutput:OcamlFinalRuntimeUseAuthority):OcamlTargetLoweredFunction {
		if (fact == null)
			throw "OCaml target function lowering requires a normalized function";
		return OcamlTargetExpressionLowerer.lowerFunction(fact, profile, finalOutput);
	}

	public static function build(fact:OcamlTargetFunctionFact):OcamlExpr {
		if (fact == null)
			throw "OCaml target function lowering requires a normalized function";
		return OcamlTargetExpressionLowerer.buildFunction(fact);
	}
}
