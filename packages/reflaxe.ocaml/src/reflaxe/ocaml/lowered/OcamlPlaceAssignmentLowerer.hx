package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.ast.OcamlExpr;

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

	/** Lowers one metadata-marked assignment or returns a deterministic invariant failure. */
	public function lower(metadata:MetadataEntry, expression:TypedExpr, buildExpr:TypedExpr->OcamlExpr,
			freshTemporary:String->String):OcamlPlaceAssignmentLoweringResult {
		final plan = switch (expression.expr) {
			case TBinop(OpAssign, left, right): planner.planSimpleAssignment(metadata, expression, left, right);
			case _: null;
		}
		if (plan == null)
			return Invalid("target-owned place metadata reached an unsupported expression shape");

		final errors = OcamlPlaceAssignmentValidator.validate(plan);
		if (errors.length > 0)
			return Invalid(errors.join("; ") + " (origin " + plan.originId + ")");

		#if macro
		final includeStandardLibrary = haxe.macro.Context.defined("ocaml_lowering_report_include_std");
		#else
		final includeStandardLibrary = false;
		#end
		if ((!context.currentIsHaxeStd && !OcamlLoweredOrigin.isTargetLibrarySource(plan.source)) || includeStandardLibrary) {
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

		return Lowered(OcamlPlaceAssignmentEmitter.emit(plan, buildExpr, freshTemporary));
	}
}
#end
