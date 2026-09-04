package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.target.OcamlTargetFunctionFact.OcamlTargetFunctionRole.StaticFunction;

/** Lowers the first complete shared-target function family into OCaml syntax. **/
class OcamlTargetFunctionLowerer {
	public static function build(fact:OcamlTargetFunctionFact):OcamlExpr {
		if (fact == null)
			throw "OCaml target function lowering requires a normalized function";
		if (fact.role != StaticFunction || fact.copyArgumentTypeDisplays().length != 0 || fact.returnTypeDisplay != "Void")
			throw "OCaml target function lowerer received an unsupported function contract";
		final body = OcamlTargetExpressionLowerer.build(fact.body);
		return OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [body]));
	}
}
