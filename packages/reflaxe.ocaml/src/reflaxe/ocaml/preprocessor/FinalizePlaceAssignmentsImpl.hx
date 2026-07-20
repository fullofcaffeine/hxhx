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
	Seals admitted place operations after every generic expression rewrite.

	The early protection pass prevents generic value normalization from changing
	place semantics. This final pass consumes that transient envelope, recomputes
	admission on the exact resulting tree, and assigns the only origins accepted
	by semantic place lowering. No expression preprocessor may follow this pass.
**/
class FinalizePlaceAssignmentsImpl extends BasePreprocessor {
	var functionId:String = "";
	var ordinal:Int = 0;
	var currentModuleId:String = "";
	var currentTypeName:String = "";

	public function new() {}

	public function process(data:ClassFuncData, compiler:BaseCompiler):Void {
		if (data.expr == null)
			return;
		functionId = data.id;
		ordinal = 0;
		currentModuleId = data.classType.module;
		currentTypeName = data.classType.name;
		data.setExpr(assignOrigins(consumeProtection(data.expr)));
	}

	function consumeProtection(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(metadata, child) if (OcamlLoweredOrigin.isPlaceProtection(metadata)):
				consumeProtection(child);
			case _:
				TypedExprTools.map(expression, consumeProtection);
		}
	}

	function assignOrigins(expression:TypedExpr):TypedExpr {
		final admitted = OcamlPlaceInputPolicy.admitsExpression(expression, currentModuleId, currentTypeName);
		var id:Null<String> = null;
		if (admitted) {
			id = OcamlLoweredOrigin.placeId(functionId, ordinal);
			ordinal += 1;
		}

		final mapped = TypedExprTools.map(expression, assignOrigins);
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
