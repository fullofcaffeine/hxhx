package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.target.OcamlTargetExpressionLowerer.OcamlTargetLoweredExpression;

/** A lowered function retains its callable type for module interfaces and dependency checks. **/
typedef OcamlTargetLoweredFunction = {
	> OcamlTargetLoweredExpression,
	final signature:OcamlTypeExpr;
}

/**
	Lowers admitted source arguments and bodies into OCaml function syntax.

	Instance-method output has only the source arguments. The class emitter must
	prepend its existing receiver parameter and preserve its record layout and dispatch.
	This lowerer does not construct objects or bind method values to receivers.
**/
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
