package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.OcamlProfileContract;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArrayElementPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredInstanceFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReport;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticFieldPlace;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlPlaceAssignmentEmitter.OcamlIntAdditionEmission;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Outcome of attempting the target-owned assignment lowering path. */
enum OcamlPlaceAssignmentLoweringResult {
	Lowered(expression:OcamlExpr);
	Invalid(message:String);
}

/**
	Consumes sealed place plans and constructs their target syntax.

	Planning and primary validation finish before this component runs. The legacy
	expression builder supplies recursive child construction and temporary-name
	allocation, but neither component inspects the typed operation to choose its
	place, evaluation schedule, conversion, writeback, or result behavior.
**/
class OcamlPlaceAssignmentLowerer {
	final context:CompilationContext;
	final registry:OcamlFunctionPlanRegistry;

	public function new(context:CompilationContext, registry:OcamlFunctionPlanRegistry) {
		this.context = context;
		this.registry = registry;
	}

	static function invalid(errors:Array<String>, originId:String):OcamlPlaceAssignmentLoweringResult {
		return Invalid(errors.join("; ") + " (origin " + originId + ")");
	}

	/**
		Consumes the exact `HxInt.add` permission owned by one sealed mutation.

		Only the returned addition subtree is reconciled here. Child expressions may
		contain independently sealed operations, so their runtime permissions remain
		owned and checked by their own lowerers.
	**/
	function emitAuthorizedIntAddition(binding:OcamlFunctionPlanBinding, requirementIds:Array<String>, occurrences:Array<OcamlRuntimeUseOccurrence>,
			emit:OcamlRuntimeReference->OcamlIntAdditionEmission):OcamlExpr {
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
		final authority = new OcamlRuntimeUseAuthority(planRevision, activeProfile, context.runtimeRequirementsByIds(requirementIds), occurrences,
			context.finalRuntimeUses);
		final occurrence = occurrences[0];
		final reference = authority.expressionIdentifier(occurrence.id, planRevision, occurrence.exactSymbol);
		final emission = emit(reference);
		authority.reconcileExpression(emission.runtimeAddition);
		return emission.expression;
	}

	static function instancePlaceReport(place:OcamlLoweredInstanceFieldPlace):OcamlLoweredPlaceReport {
		return {
			id: place.id,
			kind: place.kind,
			ownerModuleId: place.ownerModuleId,
			ownerTypeName: place.ownerTypeName,
			targetSymbolId: place.targetSymbolId,
			fieldName: place.fieldName,
			targetFieldName: place.targetFieldName,
			receiverSemanticTypeId: place.receiverSemanticTypeId,
			receiverCarrierTypeId: place.receiverCarrierTypeId,
			receiverRepresentationId: place.receiverRepresentationId,
			receiverRepresentationReason: place.receiverRepresentationReason,
			semanticTypeId: place.semanticTypeId,
			carrierTypeId: place.carrierTypeId,
			representationId: place.representationId,
			representationReason: place.representationReason
		};
	}

	static function staticPlaceReport(place:OcamlLoweredStaticFieldPlace):OcamlLoweredPlaceReport {
		return {
			id: place.id,
			kind: place.kind,
			ownerModuleId: place.ownerModuleId,
			ownerTypeName: place.ownerTypeName,
			targetSymbolId: place.targetSymbolId,
			fieldName: place.fieldName,
			targetModuleName: place.targetModuleName,
			targetValueName: place.targetValueName,
			staticAccess: place.staticAccess,
			forwardDeclarationRequired: place.forwardDeclarationRequired,
			semanticTypeId: place.semanticTypeId,
			carrierTypeId: place.carrierTypeId,
			representationId: place.representationId,
			representationReason: place.representationReason
		};
	}

	static function arrayPlaceReport(place:OcamlLoweredArrayElementPlace):OcamlLoweredPlaceReport {
		return {
			id: place.id,
			kind: place.kind,
			ownerModuleId: place.ownerModuleId,
			ownerTypeName: place.ownerTypeName,
			targetSymbolId: place.targetSymbolId,
			fieldName: place.fieldName,
			receiverSemanticTypeId: place.receiverSemanticTypeId,
			receiverDisplayType: place.receiverDisplayType,
			receiverCarrierTypeId: place.receiverCarrierTypeId,
			receiverRepresentationId: place.receiverRepresentationId,
			receiverRepresentationReason: place.receiverRepresentationReason,
			indexSemanticTypeId: place.indexSemanticTypeId,
			indexDisplayType: place.indexDisplayType,
			indexCarrierTypeId: place.indexCarrierTypeId,
			indexRepresentationId: place.indexRepresentationId,
			indexRepresentationReason: place.indexRepresentationReason,
			targetModuleName: place.targetModuleName,
			targetLoadName: place.targetLoadName,
			targetStoreName: place.targetStoreName,
			semanticTypeId: place.semanticTypeId,
			carrierTypeId: place.carrierTypeId,
			representationId: place.representationId,
			representationReason: place.representationReason
		};
	}

	function shouldRecord(source:OcamlLoweredSourceSpan):Bool {
		#if macro
		final includeStandardLibrary = haxe.macro.Context.defined("ocaml_lowering_report_include_std");
		#else
		final includeStandardLibrary = false;
		#end
		return (!context.currentIsHaxeStd && !OcamlLoweredOrigin.isTargetLibrarySource(source)) || includeStandardLibrary;
	}

	/** Looks up and emits one plan that was validated before syntax construction. */
	public function lower(originId:String, binding:OcamlFunctionPlanBinding, buildExpr:TypedExpr->OcamlExpr,
			freshTemporary:String->String):OcamlPlaceAssignmentLoweringResult {
		final resolution = registry.resolve(originId, binding);
		if (resolution.error != null)
			return Invalid(resolution.error);
		final sealed = resolution.plan;
		if (sealed == null)
			return Invalid('sealed plan lookup for origin "$originId" returned no plan');
		final planned:OcamlLoweredPlaceOperation = sealed.operation;

		return switch (planned) {
			case Simple(plan):
				final errors = OcamlPlaceAssignmentValidator.validateSimple(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "simple-assignment",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: instancePlaceReport(plan.place),
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: []
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitSimple(plan, buildExpr, freshTemporary));
				}
			case StaticSimple(plan):
				final errors = OcamlPlaceAssignmentValidator.validateStaticSimple(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "static-simple-assignment",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: staticPlaceReport(plan.place),
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: []
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitStaticSimple(plan, buildExpr, freshTemporary));
				}
			case StaticCompound(plan):
				final errors = OcamlPlaceAssignmentValidator.validateStaticCompoundIntAdd(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "static-compound-assignment",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: staticPlaceReport(plan.place),
							operation: plan.operation,
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: plan.runtimeUseOccurrences
						});
					}
					Lowered(emitAuthorizedIntAddition(binding, plan.runtimeRequirementIds, plan.runtimeUseOccurrences,
						reference -> OcamlPlaceAssignmentEmitter.emitStaticCompoundIntAdd(plan, reference, buildExpr, freshTemporary)));
				}
			case StaticUpdate(plan):
				final errors = OcamlPlaceAssignmentValidator.validateStaticIntUpdate(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "static-int-update",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: staticPlaceReport(plan.place),
							operation: plan.operation,
							sourceOperator: plan.sourceOperator,
							fixity: plan.fixity,
							delta: plan.delta,
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: plan.runtimeUseOccurrences
						});
					}
					Lowered(emitAuthorizedIntAddition(binding, plan.runtimeRequirementIds, plan.runtimeUseOccurrences,
						reference -> OcamlPlaceAssignmentEmitter.emitStaticIntUpdate(plan, reference, freshTemporary)));
				}
			case ArraySimple(plan):
				final errors = OcamlPlaceAssignmentValidator.validateArraySimple(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "array-simple-assignment",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: arrayPlaceReport(plan.place),
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: plan.runtimeUseOccurrences
						});
					}
					final runtimePlanRevision = OcamlRuntimeUseModel.planRevision(binding);
					final activeProfile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
					final runtimeAuthority = new OcamlRuntimeUseAuthority(runtimePlanRevision, activeProfile,
						context.runtimeRequirementsByIds(plan.runtimeRequirementIds), plan.runtimeUseOccurrences, context.finalRuntimeUses);
					final runtimeUse = plan.runtimeUseOccurrences[0];
					final runtimeStoreReference = runtimeAuthority.expressionIdentifier(runtimeUse.id, runtimePlanRevision, runtimeUse.exactSymbol);
					final emission = OcamlPlaceAssignmentEmitter.emitArraySimple(plan, runtimeStoreReference, buildExpr, freshTemporary);
					// Reconcile the completed store call here. Nested child expressions own
					// separate sealed plans and are checked by their own authorities.
					runtimeAuthority.reconcileExpression(emission.runtimeStore);
					Lowered(emission.expression);
				}
			case ArrayCompound(plan):
				final errors = OcamlPlaceAssignmentValidator.validateArrayCompoundIntAdd(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "array-compound-assignment",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: arrayPlaceReport(plan.place),
							operation: plan.operation,
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: plan.runtimeUseOccurrences
						});
					}
					Lowered(emitAuthorizedIntAddition(binding, plan.runtimeRequirementIds, plan.runtimeUseOccurrences,
						reference -> OcamlPlaceAssignmentEmitter.emitArrayCompoundIntAdd(plan, reference, buildExpr, freshTemporary)));
				}
			case ArrayUpdate(plan):
				final errors = OcamlPlaceAssignmentValidator.validateArrayIntUpdate(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "array-int-update",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: arrayPlaceReport(plan.place),
							operation: plan.operation,
							sourceOperator: plan.sourceOperator,
							fixity: plan.fixity,
							delta: plan.delta,
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: plan.runtimeUseOccurrences
						});
					}
					Lowered(emitAuthorizedIntAddition(binding, plan.runtimeRequirementIds, plan.runtimeUseOccurrences,
						reference -> OcamlPlaceAssignmentEmitter.emitArrayIntUpdate(plan, reference, buildExpr, freshTemporary)));
				}
			case Compound(plan):
				final errors = OcamlPlaceAssignmentValidator.validateCompoundIntAdd(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "compound-assignment",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: instancePlaceReport(plan.place),
							operation: plan.operation,
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: plan.runtimeUseOccurrences
						});
					}
					Lowered(emitAuthorizedIntAddition(binding, plan.runtimeRequirementIds, plan.runtimeUseOccurrences,
						reference -> OcamlPlaceAssignmentEmitter.emitCompoundIntAdd(plan, reference, buildExpr, freshTemporary)));
				}
			case Update(plan):
				final errors = OcamlPlaceAssignmentValidator.validateIntUpdate(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					if (shouldRecord(plan.source)) {
						context.recordLoweredPlaceReport({
							id: plan.id,
							originId: plan.originId,
							source: plan.source,
							nodeKind: "int-update",
							semanticTypeId: plan.semanticTypeId,
							carrierTypeId: plan.carrierTypeId,
							place: instancePlaceReport(plan.place),
							operation: plan.operation,
							sourceOperator: plan.sourceOperator,
							fixity: plan.fixity,
							delta: plan.delta,
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds,
							runtimeUseOccurrences: plan.runtimeUseOccurrences
						});
					}
					Lowered(emitAuthorizedIntAddition(binding, plan.runtimeRequirementIds, plan.runtimeUseOccurrences,
						reference -> OcamlPlaceAssignmentEmitter.emitIntUpdate(plan, reference, buildExpr, freshTemporary)));
				}
		}
	}
}
#end
