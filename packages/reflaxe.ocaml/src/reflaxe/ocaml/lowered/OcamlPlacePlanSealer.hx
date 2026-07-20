package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Position;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;

private typedef OcamlPlaceRuntimeFacts = {
	final decisionId:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final requirementIds:Array<String>;
}

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

	static function runtimeFacts(operation:OcamlLoweredPlaceOperation):OcamlPlaceRuntimeFacts {
		return switch (operation) {
			case Simple(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case StaticSimple(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case ArraySimple(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case Compound(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case StaticCompound(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case ArrayCompound(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case Update(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case StaticUpdate(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
			case ArrayUpdate(plan): factsFromPlan(plan.id, plan.originId, plan.source, plan.semanticTypeId, plan.runtimeRequirementIds);
		}
	}

	static function factsFromPlan(decisionId:String, originId:String, source:OcamlLoweredSourceSpan, semanticTypeId:String,
			requirementIds:Array<String>):OcamlPlaceRuntimeFacts {
		return {
			decisionId: decisionId,
			originId: originId,
			source: source,
			semanticTypeId: semanticTypeId,
			requirementIds: requirementIds
		};
	}

	/** Plans, validates, and seals one exact function-body revision. */
	public function seal(data:ClassFuncData):Void {
		final binding = registry.planningBindingFor(data);
		if (data.expr == null) {
			registry.sealFunction(binding);
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
					final runtime = runtimeFacts(operation);
					context.recordPlaceRuntimeRequirements(runtime.decisionId, runtime.originId, runtime.source, runtime.semanticTypeId,
						runtime.requirementIds);
					registry.register(binding, operation);
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
		registry.sealFunction(binding);
		final finalError = registry.validateBinding(binding, markerOriginIds);
		if (finalError != null)
			fail(finalError, data.expr.pos);
	}
}
#end
