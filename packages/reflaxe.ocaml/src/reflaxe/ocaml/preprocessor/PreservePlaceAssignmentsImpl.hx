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
	Protects admitted place operations while generic Reflaxe rewrites run.

	Reflaxe's generic Everything-Is-An-Expression sanitizer normally turns an
	assignment used as a value into a write followed by a copied left-hand-side
	read. That is unsound for effectful receivers. This early pass adds a transient
	target-owned envelope only to source shapes that have a complete lowered model.
	A distinct final pass removes the envelope and assigns stable origins on the
	exact post-rewrite body.
**/
class PreservePlaceAssignmentsImpl extends BasePreprocessor {
	var currentModuleId:String = "";
	var currentTypeName:String = "";

	public function new() {}

	public function process(data:ClassFuncData, compiler:BaseCompiler):Void {
		if (data.expr == null)
			return;
		currentModuleId = data.classType.module;
		currentTypeName = data.classType.name;
		data.setExpr(transform(data.expr));
	}

	function transform(expression:TypedExpr):TypedExpr {
		final admitted = OcamlPlaceInputPolicy.admitsExpression(expression, currentModuleId, currentTypeName);
		final mapped = TypedExprTools.map(expression, transform);
		if (!admitted)
			return mapped;
		return {
			expr: TMeta(OcamlLoweredOrigin.protection(expression.pos), mapped),
			pos: expression.pos,
			t: expression.t
		};
	}
}
#end
