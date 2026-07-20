package reflaxe.ocaml.preprocessor;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.BaseCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlPlaceInputPolicy;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.preprocessors.BasePreprocessor;

/**
	Seals admitted place operations after every generic expression rewrite.

	The early protection pass prevents generic value normalization from changing
	place semantics. This final pass consumes that transient envelope, recomputes
	admission on the exact resulting tree, and assigns the only origins accepted
	by semantic place lowering. No expression preprocessor may follow this pass.
**/
class FinalizePlaceAssignmentsImpl extends BasePreprocessor {
	public static inline final ID = "reflaxe.ocaml.finalize-place-assignments";

	var functionId:String = "";
	var ordinal:Int = 0;
	var currentModuleId:String = "";
	var currentTypeName:String = "";

	public function new() {}

	public function process(data:ClassFuncData, compiler:BaseCompiler):Void {
		final ocamlCompiler:OcamlCompiler = cast compiler;
		if (data.expr == null) {
			ocamlCompiler.sealFunctionPlans(data);
			return;
		}
		functionId = data.id;
		ordinal = 0;
		currentModuleId = data.classType.module;
		currentTypeName = data.classType.name;
		data.setExpr(finalizeProtection(data.expr, ocamlCompiler.functionPlanRegistry));
		ocamlCompiler.sealFunctionPlans(data);
	}

	override public function semanticLifecycleId():String {
		return ID;
	}

	function finalizeProtection(expression:TypedExpr, registry:OcamlFunctionPlanRegistry):TypedExpr {
		return switch (expression.expr) {
			case TMeta(metadata, child) if (OcamlLoweredOrigin.isPlaceProtection(metadata)):
				final protectionId = OcamlLoweredOrigin.readProtectionId(metadata);
				if (protectionId == null)
					fail("an early place-protection marker has no valid stable identity", expression);
				final originId = OcamlLoweredOrigin.placeId(functionId, ordinal++);
				registry.recordProtectionReplacement(protectionId, originId);
				final mappedChild = TypedExprTools.map(child, candidate -> finalizeProtection(candidate, registry));
				if (!OcamlPlaceInputPolicy.admitsExpression(mappedChild, currentModuleId, currentTypeName))
					fail('early protection "$protectionId" no longer wraps an operation supported by the final place planner', mappedChild);
				{
					expr: TMeta(OcamlLoweredOrigin.metadata(originId, expression.pos), mappedChild),
					pos: expression.pos,
					t: expression.t
				};
			case TMeta(metadata, _) if (metadata.name == OcamlLoweredOrigin.PLACE_META):
				fail("a final place origin existed before the final planning boundary", expression);
			case _:
				TypedExprTools.map(expression, candidate -> finalizeProtection(candidate, registry));
		};
	}

	static function fail(message:String, expression:TypedExpr):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-lowering:place-finalization]: " + message;
		#if macro
		haxe.macro.Context.error(diagnostic, expression.pos);
		#end
		throw diagnostic;
	}
}
#end
