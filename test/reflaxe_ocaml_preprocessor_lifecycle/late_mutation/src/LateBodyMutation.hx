#if macro
import haxe.macro.Type.TypedExpr;
import reflaxe.BaseCompiler;
import reflaxe.ReflectCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.preprocessors.BasePreprocessor;
import reflaxe.preprocessors.ExpressionPreprocessor;
#end

/** Installs a test-only rewrite that lies about preserving a sealed function. */
class LateBodyMutation {
	#if macro
	public static function install():Void {
		ReflectCompiler.onCompileBegin((compiler:OcamlCompiler) -> {
			compiler.expressionPreprocessors.push(ExpressionPreprocessor.Custom(new LateBodyMutationImpl()));
		});
	}
	#end
}

#if macro
private class LateBodyMutationImpl extends BasePreprocessor {
	public function new() {}

	/** Claims a normal preserving identity so the exact-body check must catch the lie. */
	override public function semanticLifecycleId():String {
		return "remove-unnecessary-blocks";
	}

	public function process(data:ClassFuncData, compiler:BaseCompiler):Void {
		final body:Null<TypedExpr> = data.expr;
		if (body == null)
			return;
		data.setExpr({expr: TBlock([body]), pos: body.pos, t: body.t});
	}
}
#end
