package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArrayElementPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredInstanceFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReport;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticFieldPlace;

/** Outcome of attempting the target-owned assignment lowering path. */
enum OcamlPlaceAssignmentLoweringResult {
	Lowered(expression:OcamlExpr);
	Invalid(message:String);
}

/**
	Owns planning, validation, inspection, and syntax construction for admitted
	place operations.

	The legacy expression builder supplies recursive child construction and
	temporary-name allocation, but it does not inspect or reconstruct any of the
	semantic place facts sealed here.
**/
class OcamlPlaceAssignmentLowerer {
	final context:CompilationContext;
	final planner:OcamlPlaceAssignmentPlanner;

	public function new(context:CompilationContext) {
		this.context = context;
		this.planner = new OcamlPlaceAssignmentPlanner(context);
	}

	static function invalid(errors:Array<String>, originId:String):OcamlPlaceAssignmentLoweringResult {
		return Invalid(errors.join("; ") + " (origin " + originId + ")");
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

	/** Lowers one metadata-marked place operation or returns an invariant failure. */
	public function lower(metadata:MetadataEntry, expression:TypedExpr, buildExpr:TypedExpr->OcamlExpr,
			freshTemporary:String->String):OcamlPlaceAssignmentLoweringResult {
		final planned:Null<OcamlLoweredPlaceOperation> = switch (expression.expr) {
			case TBinop(OpAssign, left, right):
				final instancePlan = planner.planSimpleAssignment(metadata, expression, left, right);
				if (instancePlan != null) {
					OcamlLoweredPlaceOperation.Simple(instancePlan);
				} else {
					final staticPlan = planner.planStaticSimpleAssignment(metadata, expression, left, right);
					if (staticPlan != null) {
						OcamlLoweredPlaceOperation.StaticSimple(staticPlan);
					} else {
						final arrayPlan = planner.planArraySimpleAssignment(metadata, expression, left, right);
						arrayPlan == null ? null : OcamlLoweredPlaceOperation.ArraySimple(arrayPlan);
					}
				}
			case TBinop(OpAssignOp(OpAdd), left, right):
				final instancePlan = planner.planCompoundIntAdd(metadata, expression, left, right);
				if (instancePlan != null) {
					OcamlLoweredPlaceOperation.Compound(instancePlan);
				} else {
					final staticPlan = planner.planStaticCompoundIntAdd(metadata, expression, left, right);
					if (staticPlan != null) {
						OcamlLoweredPlaceOperation.StaticCompound(staticPlan);
					} else {
						final arrayPlan = planner.planArrayCompoundIntAdd(metadata, expression, left, right);
						arrayPlan == null ? null : OcamlLoweredPlaceOperation.ArrayCompound(arrayPlan);
					}
				}
			case TUnop(operation = (OpIncrement | OpDecrement), postFix, operand):
				final instancePlan = planner.planIntUpdate(metadata, expression, operation, postFix, operand);
				if (instancePlan != null) {
					OcamlLoweredPlaceOperation.Update(instancePlan);
				} else {
					final staticPlan = planner.planStaticIntUpdate(metadata, expression, operation, postFix, operand);
					if (staticPlan != null) {
						OcamlLoweredPlaceOperation.StaticUpdate(staticPlan);
					} else {
						final arrayPlan = planner.planArrayIntUpdate(metadata, expression, operation, postFix, operand);
						arrayPlan == null ? null : OcamlLoweredPlaceOperation.ArrayUpdate(arrayPlan);
					}
				}
			case _: null;
		}
		if (planned == null)
			return Invalid("target-owned place metadata reached an unsupported operation shape");

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
							runtimeRequirementIds: plan.runtimeRequirementIds
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitStaticSimple(plan, buildExpr, freshTemporary));
				}
			case StaticCompound(plan):
				final errors = OcamlPlaceAssignmentValidator.validateStaticCompoundIntAdd(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					context.markRuntimeModule("HxInt");
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitStaticCompoundIntAdd(plan, buildExpr, freshTemporary));
				}
			case StaticUpdate(plan):
				final errors = OcamlPlaceAssignmentValidator.validateStaticIntUpdate(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					context.markRuntimeModule("HxInt");
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitStaticIntUpdate(plan, freshTemporary));
				}
			case ArraySimple(plan):
				final errors = OcamlPlaceAssignmentValidator.validateArraySimple(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					context.markRuntimeModule("HxArray");
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitArraySimple(plan, buildExpr, freshTemporary));
				}
			case ArrayCompound(plan):
				final errors = OcamlPlaceAssignmentValidator.validateArrayCompoundIntAdd(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					context.markRuntimeModule("HxArray");
					context.markRuntimeModule("HxInt");
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitArrayCompoundIntAdd(plan, buildExpr, freshTemporary));
				}
			case ArrayUpdate(plan):
				final errors = OcamlPlaceAssignmentValidator.validateArrayIntUpdate(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					context.markRuntimeModule("HxArray");
					context.markRuntimeModule("HxInt");
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitArrayIntUpdate(plan, buildExpr, freshTemporary));
				}
			case Compound(plan):
				final errors = OcamlPlaceAssignmentValidator.validateCompoundIntAdd(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					context.markRuntimeModule("HxInt");
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitCompoundIntAdd(plan, buildExpr, freshTemporary));
				}
			case Update(plan):
				final errors = OcamlPlaceAssignmentValidator.validateIntUpdate(plan);
				if (errors.length > 0) invalid(errors, plan.originId); else {
					context.markRuntimeModule("HxInt");
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
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitIntUpdate(plan, buildExpr, freshTemporary));
				}
		}
	}
}
#end
