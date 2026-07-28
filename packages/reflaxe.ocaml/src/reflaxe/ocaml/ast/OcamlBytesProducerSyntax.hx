package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerKind;

/**
	Constructs OCaml syntax from one already-validated Bytes producer decision.

	This helper does not classify Haxe calls or choose runtime dependencies. The
	typed planner has already done both; this layer only preserves argument order
	and selects the matching `HxBytes` function spelling.
**/
class OcamlBytesProducerSyntax {
	public static function build(decision:OcamlBytesProducerDecision, arguments:Array<TypedExpr>, buildArgument:TypedExpr->OcamlExpr):OcamlExpr {
		if (arguments.length != decision.argumentCount)
			throw 'reflaxe.ocaml [ocaml-bytes:syntax-arity-mismatch]: producer "${decision.id}" expected ${decision.argumentCount} arguments but received ${arguments.length}';
		final built = [for (index in decision.argumentEvaluationOrder) buildArgument(arguments[index])];
		return switch (decision.kind) {
			case Constructor:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "create"), [built[0], built[1]]);
			case Alloc:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "alloc"), [built[0]]);
			case OfString:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "ofString"), [built[0], OcamlExpr.EConst(OcamlConst.CUnit)]);
			case OfData:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "ofData"), [built[0], OcamlExpr.EConst(OcamlConst.CUnit)]);
			case OfHex:
				OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxBytes"), "ofHex"), [built[0]]);
		}
	}
}
#end
