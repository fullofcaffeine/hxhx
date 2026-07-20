package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Position;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.CompilationContext;

/**
	Builds every admitted place plan from the final preprocessed function body.

	This is the last source-semantic step for the admitted family. It requires a
	stable origin marker, selects and validates the complete plan, registers that
	plan against the exact function-body revision, and rejects an admitted
	operation that reached this boundary without early protection.
**/
class OcamlPlacePlanSealer {
	final context:CompilationContext;
	final registry:OcamlPlacePlanRegistry;

	public function new(context:CompilationContext, registry:OcamlPlacePlanRegistry) {
		this.context = context;
		this.registry = registry;
	}

	static function fail(message:String, position:Position):Dynamic {
		final diagnostic = "reflaxe.ocaml [ocaml-lowering:plan-seal]: " + message;
		#if macro
		haxe.macro.Context.error(diagnostic, position);
		#end
		throw diagnostic;
	}

	/** Plans, validates, and seals one exact function-body revision. */
	public function seal(data:ClassFuncData):Void {
		if (data.expr == null) {
			registry.sealFunction(data);
			return;
		}

		final moduleId = data.classType.module;
		final typeName = data.classType.name;
		final planner = new OcamlPlaceAssignmentPlanner(context, moduleId, typeName);
		final seen:Map<String, Bool> = [];
		final markerOriginIds:Array<String> = [];

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TMeta(metadata, child) if (metadata.name == OcamlLoweredOrigin.PLACE_META):
					final originId = OcamlLoweredOrigin.readPlaceId(metadata);
					if (originId == null)
						fail("a final place marker has no valid stable identity", expression.pos);
					if (seen.exists(originId))
						fail('place origin "$originId" occurs more than once in function "${data.id}"', expression.pos);
					seen.set(originId, true);
					final operation = planner.plan(metadata, child);
					if (operation == null)
						fail('place origin "$originId" no longer wraps an operation admitted by the final typed planner', child.pos);
					final errors = OcamlPlaceAssignmentValidator.validate(operation);
					if (errors.length > 0)
						fail(errors.join("; ") + ' (origin "$originId")', child.pos);
					registry.register(data, operation);
					markerOriginIds.push(originId);
					// The wrapper owns this operation. Continue with its children so a
					// nested origin receives its own independently sealed plan.
					TypedExprTools.iter(child, visit);
				case _:
					if (OcamlPlaceInputPolicy.admitsExpression(expression, moduleId, typeName)) {
						fail("an admitted assignment or update reached final planning without its early protection marker", expression.pos);
					}
					TypedExprTools.iter(expression, visit);
			}
		}

		visit(data.expr);
		registry.sealFunction(data);
		final finalError = registry.validateFunction(data, markerOriginIds);
		if (finalError != null)
			fail(finalError, data.expr.pos);
	}
}
#end
