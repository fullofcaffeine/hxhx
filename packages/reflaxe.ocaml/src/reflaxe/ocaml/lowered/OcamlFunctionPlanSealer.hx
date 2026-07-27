package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Position;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlanner;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

private typedef OcamlPlaceRuntimeFacts = {
	final decisionId:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final requirementIds:Array<String>;
}

/**
	Builds every admitted lowered plan from the final preprocessed function body.

	This is the last source-semantic step for admitted place operations and local
	storage. It plans both from the same body revision, rejects an admitted
	operation that lost early protection, and seals one function record before
	syntax construction begins.
**/
class OcamlFunctionPlanSealer {
	final context:CompilationContext;
	final registry:OcamlFunctionPlanRegistry;
	final representations:OcamlRepresentationRegistry;
	final staticStorage:OcamlStaticStoragePlan;

	public function new(context:CompilationContext, registry:OcamlFunctionPlanRegistry, representations:OcamlRepresentationRegistry,
			staticStorage:OcamlStaticStoragePlan) {
		this.context = context;
		this.registry = registry;
		this.representations = representations;
		this.staticStorage = staticStorage;
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
		final callPlanner = new OcamlCallPlanner(representations, binding);
		final callableBoundary = callPlanner.boundaryFor(data);
		final constructionBoundary = callPlanner.constructionBoundaryFor(data);
		if (data.expr == null) {
			registry.sealFunction(binding, OcamlLocalStoragePlanner.planExpressions([]), new OcamlLocalRepresentationPlan([]), new OcamlCallPlan([]),
				callableBoundary, constructionBoundary);
			return;
		}
		final localStorage = OcamlLocalStoragePlanner.planExpression(data.expr);
		final preliminaryCalls = callPlanner.plan(data.expr);
		final localRepresentations = OcamlLocalRepresentationPlanner.planExpression(data.expr, localStorage, representations, binding,
			preliminaryCalls.preservesNullableBoolArgument, preliminaryCalls.producesNullableBool, preliminaryCalls.producesExactString);
		final calls = new OcamlCallPlanner(representations, binding, localRepresentations).plan(data.expr);

		final moduleId = data.classType.module;
		final typeName = data.classType.name;
		final planner = new OcamlPlaceAssignmentPlanner(context, moduleId, typeName, representations, localRepresentations, staticStorage);
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
					validateRepresentationReferences(operation, binding.programRevision, child.pos);
					final runtime = runtimeFacts(operation);
					context.recordPlaceRuntimeRequirements(runtime.decisionId, runtime.originId, runtime.source, runtime.semanticTypeId,
						runtime.requirementIds);
					registry.register(binding, operation);
					markerOriginIds.push(originId);
					// The wrapper owns this operation. Continue with its children so a
					// nested origin receives its own independently sealed plan.
					TypedExprTools.iter(child, visit);
				case _:
					if (OcamlPlaceInputPolicy.admitsExpression(expression, moduleId, typeName, staticStorage)) {
						fail("an admitted assignment or update reached final planning without its early protection marker", expression.pos);
					}
					TypedExprTools.iter(expression, visit);
			}
		}

		visit(data.expr);
		validateLocalRepresentationReferences(localStorage, localRepresentations, binding.programRevision, data.expr.pos);
		validateCallRepresentationReferences(calls, callableBoundary, constructionBoundary, binding.programRevision, data.expr.pos);
		registry.sealFunction(binding, localStorage, localRepresentations, calls, callableBoundary, constructionBoundary);
		final finalError = registry.validateBinding(binding, markerOriginIds);
		if (finalError != null)
			fail(finalError, data.expr.pos);
	}

	function validateCallRepresentationReferences(calls:OcamlCallPlan, callableBoundary:Null<OcamlCallableBoundaryPlan>,
			constructionBoundary:Null<OcamlCallableBoundaryPlan>, programRevision:String, position:Position):Void {
		for (call in calls.decisions()) {
			if (call.receiver != null)
				validateCallValue(call.receiver, programRevision, 'call "${call.id}" receiver', position);
			for (index in 0...call.arguments.length)
				validateCallValue(call.arguments[index], programRevision, 'call "${call.id}" argument $index', position);
			if (call.result != null)
				validateCallValue(call.result, programRevision, 'call "${call.id}" result', position);
		}
		if (callableBoundary != null) {
			validateBoundaryRepresentationReferences(callableBoundary, programRevision, position);
		}
		if (constructionBoundary != null)
			validateBoundaryRepresentationReferences(constructionBoundary, programRevision, position);
	}

	function validateBoundaryRepresentationReferences(boundary:OcamlCallableBoundaryPlan, programRevision:String, position:Position):Void {
		if (boundary.receiver != null)
			validateCallValue(boundary.receiver, programRevision, 'callable boundary "${boundary.id}" receiver', position);
		for (index in 0...boundary.arguments.length)
			validateCallValue(boundary.arguments[index], programRevision, 'callable boundary "${boundary.id}" argument $index', position);
		if (boundary.result != null)
			validateCallValue(boundary.result, programRevision, 'callable boundary "${boundary.id}" result', position);
	}

	function validateCallValue(value:OcamlCallValuePlan, programRevision:String, owner:String, position:Position):Void {
		validateCallValueSide(value.inputRepresentationId, value.inputSemanticTypeId, value.inputCarrierTypeId, programRevision, owner + " input", position);
		validateCallValueSide(value.outputRepresentationId, value.outputSemanticTypeId, value.outputCarrierTypeId, programRevision, owner + " output",
			position);
	}

	function validateCallValueSide(representationId:String, semanticTypeId:String, carrierTypeId:String, programRevision:String, owner:String,
			position:Position):Void {
		final decision = try {
			representations.require(representationId, programRevision);
		} catch (error:Dynamic) {
			fail(Std.string(error), position);
		}
		if (decision.semanticTypeId != semanticTypeId
			|| decision.carrierTypeId != carrierTypeId
			|| decision.domain != OcamlRepresentationDomain.InternalValue) {
			fail('$owner expects $semanticTypeId -> $carrierTypeId in ${OcamlRepresentationDomain.InternalValue}, but ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain}',
				position);
		}
	}

	function validateLocalRepresentationReferences(storage:OcamlLocalStoragePlan, plan:OcamlLocalRepresentationPlan, programRevision:String,
			position:Position):Void {
		for (reference in plan.references()) {
			final decision = try {
				representations.require(reference.representationId, programRevision);
			} catch (error:Dynamic) {
				fail(Std.string(error), position);
			}
			if (decision.semanticTypeId != reference.semanticTypeId || decision.domain != reference.domain) {
				fail('local ${reference.localId} expects ${reference.semanticTypeId} in representation domain ${reference.domain}, but ${decision.id} selects ${decision.semanticTypeId} in ${decision.domain}',
					position);
			}
			if (OcamlMonomorphicClassMaterializer.isNominalClass(decision)
				&& storage.isCaptured(reference.localId)
				&& !storage.isImmutableCapture(reference.localId)) {
				fail('captured nominal local ${reference.localId} requires mutable shared storage, so it cannot consume immutable representation ${decision.id}',
					position);
			}
		}
	}

	function validateRepresentationReferences(operation:OcamlLoweredPlaceOperation, programRevision:String, position:Position):Void {
		switch (operation) {
			case Simple(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.InstanceField, programRevision, position);
				validateAdmittedInstanceReceiver(plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					programRevision, position);
			case StaticSimple(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.StaticField, programRevision, position);
			case ArraySimple(plan):
				validateArrayRepresentationReferences(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					plan.place.indexRepresentationId, plan.place.indexSemanticTypeId, plan.place.indexCarrierTypeId, programRevision, position);
			case Compound(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.InstanceField, programRevision, position);
				validateAdmittedInstanceReceiver(plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					programRevision, position);
			case StaticCompound(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.StaticField, programRevision, position);
			case ArrayCompound(plan):
				validateArrayRepresentationReferences(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					plan.place.indexRepresentationId, plan.place.indexSemanticTypeId, plan.place.indexCarrierTypeId, programRevision, position);
			case Update(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.InstanceField, programRevision, position);
				validateAdmittedInstanceReceiver(plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					programRevision, position);
			case StaticUpdate(plan):
				validateRepresentationReference(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					OcamlRepresentationDomain.StaticField, programRevision, position);
			case ArrayUpdate(plan):
				validateArrayRepresentationReferences(plan.place.representationId, plan.place.semanticTypeId, plan.place.carrierTypeId,
					plan.place.receiverRepresentationId, plan.place.receiverSemanticTypeId, plan.place.receiverCarrierTypeId,
					plan.place.indexRepresentationId, plan.place.indexSemanticTypeId, plan.place.indexCarrierTypeId, programRevision, position);
		}
	}

	function validateAdmittedInstanceReceiver(representationId:String, semanticTypeId:String, carrierTypeId:String, programRevision:String,
			position:Position):Void {
		if (!StringTools.startsWith(representationId, "representation:"))
			return;
		validateRepresentationReference(representationId, semanticTypeId, carrierTypeId, OcamlRepresentationDomain.InternalValue, programRevision, position);
	}

	function validateArrayRepresentationReferences(representationId:String, semanticTypeId:String, carrierTypeId:String, receiverRepresentationId:String,
			receiverSemanticTypeId:String, receiverCarrierTypeId:String, indexRepresentationId:String, indexSemanticTypeId:String, indexCarrierTypeId:String,
			programRevision:String, position:Position):Void {
		validateRepresentationReference(representationId, semanticTypeId, carrierTypeId, OcamlRepresentationDomain.ArrayElement, programRevision, position);
		validateRepresentationReference(receiverRepresentationId, receiverSemanticTypeId, receiverCarrierTypeId, OcamlRepresentationDomain.InternalValue,
			programRevision, position);
		validateRepresentationReference(indexRepresentationId, indexSemanticTypeId, indexCarrierTypeId, OcamlRepresentationDomain.InternalValue,
			programRevision, position);
	}

	function validateRepresentationReference(representationId:String, semanticTypeId:String, carrierTypeId:String, domain:OcamlRepresentationDomain,
			programRevision:String, position:Position):Void {
		final decision = try {
			representations.require(representationId, programRevision);
		} catch (error:Dynamic) {
			fail(Std.string(error), position);
		}
		if (decision.semanticTypeId != semanticTypeId || decision.carrierTypeId != carrierTypeId || decision.domain != domain) {
			fail('representation ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain}, but the place plan expects $semanticTypeId -> $carrierTypeId in $domain',
				position);
		}
	}
}
#end
