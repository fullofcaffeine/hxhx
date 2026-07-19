package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceAssignment;

/** Outcome of attempting the target-owned assignment lowering path. */
enum OcamlPlaceAssignmentLoweringResult {
	Lowered(expression:OcamlExpr);
	Invalid(message:String);
}

/**
	Owns planning, validation, inspection, and syntax construction for admitted
	place assignments.

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

	function shouldRecord(source:OcamlLoweredSourceSpan):Bool {
		#if macro
		final includeStandardLibrary = haxe.macro.Context.defined("ocaml_lowering_report_include_std");
		#else
		final includeStandardLibrary = false;
		#end
		return (!context.currentIsHaxeStd && !OcamlLoweredOrigin.isTargetLibrarySource(source)) || includeStandardLibrary;
	}

	/** Lowers one metadata-marked assignment or returns a deterministic invariant failure. */
	public function lower(metadata:MetadataEntry, expression:TypedExpr, buildExpr:TypedExpr->OcamlExpr,
			freshTemporary:String->String):OcamlPlaceAssignmentLoweringResult {
		final planned:Null<OcamlLoweredPlaceAssignment> = switch (expression.expr) {
			case TBinop(OpAssign, left, right):
				final plan = planner.planSimpleAssignment(metadata, expression, left, right);
				plan == null ? null : OcamlLoweredPlaceAssignment.Simple(plan);
			case TBinop(OpAssignOp(OpAdd), left, right):
				final plan = planner.planCompoundIntAdd(metadata, expression, left, right);
				plan == null ? null : OcamlLoweredPlaceAssignment.Compound(plan);
			case _: null;
		}
		if (planned == null)
			return Invalid("target-owned place metadata reached an unsupported expression shape");

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
							place: plan.place,
							conversion: plan.conversion,
							result: plan.result,
							schedule: plan.schedule,
							effects: plan.effects,
							runtimeRequirementIds: plan.runtimeRequirementIds
						});
					}
					Lowered(OcamlPlaceAssignmentEmitter.emitSimple(plan, buildExpr, freshTemporary));
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
							place: plan.place,
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
		}
	}
}
#end
