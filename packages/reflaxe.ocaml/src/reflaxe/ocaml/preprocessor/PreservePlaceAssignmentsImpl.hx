package reflaxe.ocaml.preprocessor;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.BaseCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlPlaceInputPolicy;
import reflaxe.preprocessors.BasePreprocessor;

/**
	Preserves admitted place operations until the OCaml semantic lowerer sees them.

	Reflaxe's generic Everything-Is-An-Expression sanitizer normally turns an
	assignment used as a value into a write followed by a copied left-hand-side
	read. That is unsound for effectful receivers. This pass adds target-owned
	metadata only to source shapes that have a complete lowered model.
**/
class PreservePlaceAssignmentsImpl extends BasePreprocessor {
	var functionId:String = "";
	var ordinal:Int = 0;

	public function new() {}

	public function process(data:ClassFuncData, compiler:BaseCompiler):Void {
		if (data.expr == null)
			return;
		functionId = data.id;
		ordinal = 0;
		data.setExpr(transform(data.expr));
	}

	function transform(expression:TypedExpr):TypedExpr {
		final admitted = switch (expression.expr) {
			case TBinop(OpAssign, left, right): OcamlPlaceInputPolicy.admitsSimpleInstanceField(left, right);
			case TBinop(OpAssignOp(operation), left, right): OcamlPlaceInputPolicy.admitsCompoundIntAddInstanceField(operation, left, right);
			case TUnop(operation, _, operand): OcamlPlaceInputPolicy.admitsIntUpdateInstanceField(operation, operand);
			case _: false;
		}

		var id:Null<String> = null;
		if (admitted) {
			id = OcamlLoweredOrigin.placeId(functionId, ordinal);
			ordinal += 1;
		}

		final mapped = TypedExprTools.map(expression, transform);
		if (id == null)
			return mapped;
		return {
			expr: TMeta(OcamlLoweredOrigin.metadata(id, expression.pos), mapped),
			pos: expression.pos,
			t: expression.t
		};
	}
}
#end
