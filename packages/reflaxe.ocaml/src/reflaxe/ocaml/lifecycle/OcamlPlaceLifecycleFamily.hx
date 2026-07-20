package reflaxe.ocaml.lifecycle;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.lifecycle.SemanticArtifactBinding;
import reflaxe.lifecycle.SemanticArtifactFamily;
import reflaxe.lifecycle.SemanticArtifactReplacement;
import reflaxe.lifecycle.SemanticArtifactSnapshot;
import reflaxe.lifecycle.SemanticPreprocessorAction;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlPlacePlanRegistry;
import reflaxe.ocaml.preprocessor.FinalizePlaceAssignmentsImpl;
import reflaxe.ocaml.preprocessor.InlineSwitchTempImpl;
import reflaxe.ocaml.preprocessor.PreservePlaceAssignmentsImpl;

/**
	Declares how OCaml place markers and sealed plans cross Reflaxe preprocessors.

	Reflaxe sees only stable IDs and fingerprints. This target-owned family knows
	which metadata is transient protection, which metadata names a final plan,
	and which generic passes are allowed to preserve those records.
**/
class OcamlPlaceLifecycleFamily extends SemanticArtifactFamily {
	public static inline final ID = "reflaxe.ocaml.place-plans";
	static inline final PROTECTION_FINGERPRINT = "early-protection";

	final registry:OcamlPlacePlanRegistry;

	public function new(registry:OcamlPlacePlanRegistry) {
		super(ID, SemanticArtifactBinding.StructuralEnvelope);
		this.registry = registry;
	}

	static function visitArtifacts(expression:TypedExpr, onProtection:(String, TypedExpr) -> Void, onOrigin:(String, TypedExpr) -> Void):Void {
		switch (expression.expr) {
			case TMeta(metadata, child) if (metadata.name == OcamlLoweredOrigin.PLACE_PROTECTION_META):
				final id = OcamlLoweredOrigin.readProtectionId(metadata);
				if (id != null)
					onProtection(id, expression);
				TypedExprTools.iter(child, candidate -> visitArtifacts(candidate, onProtection, onOrigin));
			case TMeta(metadata, child) if (metadata.name == OcamlLoweredOrigin.PLACE_META):
				final id = OcamlLoweredOrigin.readPlaceId(metadata);
				if (id != null)
					onOrigin(id, expression);
				TypedExprTools.iter(child, candidate -> visitArtifacts(candidate, onProtection, onOrigin));
			case _:
				TypedExprTools.iter(expression, candidate -> visitArtifacts(candidate, onProtection, onOrigin));
		}
	}

	public function snapshot(data:ClassFuncData):Array<SemanticArtifactSnapshot> {
		if (data.expr == null)
			return [];
		final planByOrigin = [for (plan in registry.plansForFunction(data.id)) plan.originId => plan];
		final snapshots:Array<SemanticArtifactSnapshot> = [];
		visitArtifacts(data.expr, (id, expression) -> snapshots.push({
			id: id,
			fingerprint: PROTECTION_FINGERPRINT,
			origin: "early protected place operation"
		}), (id, expression) -> {
			final plan = planByOrigin.get(id);
			snapshots.push({
				id: id,
				fingerprint: plan == null ? "missing-final-plan" : plan.fingerprint,
				origin: "final revision-bound place plan"
			});
		});
		return snapshots;
	}

	public function actionFor(preprocessorId:String):SemanticPreprocessorAction {
		return switch (preprocessorId) {
			case PreservePlaceAssignmentsImpl.ID | FinalizePlaceAssignmentsImpl.ID:
				SemanticPreprocessorAction.Replace;
			case InlineSwitchTempImpl.ID | "sanitize-everything-is-expression" | "remove-temporary-variables" | "prevent-repeat-variables" | "wrap-lambda-captures" | "remove-pure-expressions" | "remove-single-expression-blocks" | "remove-constant-bool-ifs" | "remove-unnecessary-blocks" | "remove-reassigned-variable-declarations" | "remove-local-variable-aliases" | "mark-unused-variables":
				SemanticPreprocessorAction.Preserve;
			case _:
				SemanticPreprocessorAction.Reject;
		}
	}

	override public function mapReplacement(preprocessorId:String, before:Array<SemanticArtifactSnapshot>,
			after:Array<SemanticArtifactSnapshot>):Null<Array<SemanticArtifactReplacement>> {
		if (StringTools.endsWith(preprocessorId, FinalizePlaceAssignmentsImpl.ID)) {
			final afterIds:Map<String, Bool> = [for (artifact in after) artifact.id => true];
			final replacements:Array<SemanticArtifactReplacement> = [];
			for (artifact in before) {
				final originId = registry.originForProtection(artifact.id);
				if (originId == null || !afterIds.exists(originId))
					return null;
				replacements.push({beforeId: artifact.id, afterId: originId});
				afterIds.remove(originId);
			}
			if (afterIds.keys().hasNext())
				return null;
			return replacements;
		}
		final result:Array<SemanticArtifactReplacement> = [];
		final remainingAfter:Map<String, Bool> = [for (artifact in after) artifact.id => true];
		for (artifact in before) {
			if (remainingAfter.exists(artifact.id)) {
				result.push({beforeId: artifact.id, afterId: artifact.id});
				remainingAfter.remove(artifact.id);
			} else {
				result.push({beforeId: artifact.id, afterId: null});
			}
		}
		for (artifact in after) {
			if (remainingAfter.exists(artifact.id))
				result.push({beforeId: null, afterId: artifact.id});
		}
		return result;
	}

	override public function validateFinal(data:ClassFuncData, artifacts:Array<SemanticArtifactSnapshot>):Null<String> {
		for (artifact in artifacts) {
			if (artifact.fingerprint == PROTECTION_FINGERPRINT)
				return 'function "${data.id}" still contains early place protection after final planning';
			if (artifact.fingerprint == "missing-final-plan")
				return 'function "${data.id}" origin "${artifact.id}" has no sealed final plan';
		}
		return registry.validateFunction(data, [for (artifact in artifacts) artifact.id]);
	}
}
#end
