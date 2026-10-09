package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlExpr;

/** Lowers the first complete shared-target function family into OCaml syntax. **/
class OcamlTargetFunctionLowerer {
	public static function build(fact:OcamlTargetFunctionFact):OcamlExpr {
		if (fact == null)
			throw "OCaml target function lowering requires a normalized function";
		return OcamlTargetExpressionLowerer.buildFunction(fact);
	}
}
