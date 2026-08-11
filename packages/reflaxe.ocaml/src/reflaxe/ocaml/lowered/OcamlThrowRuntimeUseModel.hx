package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The reason that one sealed throw uses a private OCaml runtime name. */
enum abstract OcamlThrowRuntimeUseRole(String) to String {
	final Signal = "raise-typed-haxe-exception";
	final BoxExactBoolPayload = "box-exact-bool-throw-payload";
	final TestNullableBoolPayload = "test-nullable-bool-throw-payload";
	final BoxNullableBoolPayload = "box-nullable-bool-throw-payload";
	final RecoverNullableBoolPayload = "recover-nullable-bool-throw-payload";
	final BoxEnumPayload = "box-enum-throw-payload";
}

/** The ordered private runtime calls selected by an exact sealed Haxe throw. */
typedef OcamlThrowRuntimeUsePlan = {
	final decisionId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/**
	Builds and checks private-runtime ownership for one planned Haxe throw.

	The control decision already fixes the payload conversion, runtime tags, and
	exception channel. This contract adds only permission to print the matching
	private signal and payload helpers once for that exact source occurrence.
**/
class OcamlThrowRuntimeUseContract {
	public static inline final SIGNAL_SYMBOL = "HxType.hx_throw_typed_rtti";

	/** Returns the runtime requirement identity owned by one exact throw. */
	public static function requirementId(decision:OcamlControlDecision):String {
		return decision.id + ":runtime:" + decision.runtimeCapabilityId;
	}

	/** Returns the runtime-use identity owned by one exact throw. */
	public static function runtimeUseId(decisionId:String, role:OcamlThrowRuntimeUseRole):String {
		return decisionId + ":runtime-use:" + role;
	}

	/** Derives every ordered private call selected by a valid throw decision. */
	public static function forDecision(decision:OcamlControlDecision):OcamlThrowRuntimeUsePlan {
		OcamlControlPlan.requireDecision(decision);
		if (decision.kind != OcamlControlTransferKind.Throw
			|| decision.mechanism != OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal) {
			throw 'reflaxe.ocaml [ocaml-throw:unexpected-runtime-use]: control decision "${decision.id}" is not a typed Haxe throw';
		}
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final selectedRequirementId = requirementId(decision);
		final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
		occurrences.push(occurrence(decision, planRevision, selectedRequirementId, OcamlThrowRuntimeUseRole.Signal, SIGNAL_SYMBOL, 0));
		if (decision.payload == null)
			throw 'reflaxe.ocaml [ocaml-throw:unexpected-runtime-use]: throw decision "${decision.id}" has no sealed payload';
		switch (decision.payload.conversion) {
			case OcamlControlPayloadConversion.BoxBoolAndRecoverExactValue:
				occurrences.push(occurrence(decision, planRevision, selectedRequirementId, OcamlThrowRuntimeUseRole.BoxExactBoolPayload, "HxRuntime.box_bool",
					1));
			case OcamlControlPayloadConversion.NormalizeNullableBoolThrowCarrier:
				occurrences.push(occurrence(decision, planRevision, selectedRequirementId, OcamlThrowRuntimeUseRole.TestNullableBoolPayload,
					"HxRuntime.is_null", 1));
				occurrences.push(occurrence(decision, planRevision, selectedRequirementId, OcamlThrowRuntimeUseRole.BoxNullableBoolPayload,
					"HxRuntime.box_bool", 2));
				occurrences.push(occurrence(decision, planRevision, selectedRequirementId, OcamlThrowRuntimeUseRole.RecoverNullableBoolPayload,
					"HxRuntime.unbox_bool_or_obj", 3));
			case OcamlControlPayloadConversion.BoxEnumThrowCarrier:
				occurrences.push(occurrence(decision, planRevision, selectedRequirementId, OcamlThrowRuntimeUseRole.BoxEnumPayload, "HxEnum.box_if_needed", 1));
			case _:
		}
		return {
			decisionId: decision.id,
			planRevision: planRevision,
			runtimeRequirementIds: [selectedRequirementId],
			runtimeUseOccurrences: occurrences
		};
	}

	/** Rejects a missing, stale, or conflicting throw runtime-use plan. */
	public static function requireForDecision(decision:OcamlControlDecision, plan:OcamlThrowRuntimeUsePlan):Void {
		final expected = forDecision(decision);
		if (plan == null
			|| plan.decisionId != expected.decisionId
			|| plan.planRevision != expected.planRevision
			|| plan.runtimeRequirementIds.join(",") != expected.runtimeRequirementIds.join(",")
			|| plan.runtimeUseOccurrences.length != expected.runtimeUseOccurrences.length) {
			throw 'reflaxe.ocaml [ocaml-throw:invalid-runtime-use]: throw decision "${decision.id}" does not own its exact runtime requirement and occurrences';
		}
		for (index in 0...expected.runtimeUseOccurrences.length) {
			if (!sameOccurrence(plan.runtimeUseOccurrences[index], expected.runtimeUseOccurrences[index])) {
				throw 'reflaxe.ocaml [ocaml-throw:invalid-runtime-use]: throw decision "${decision.id}" has a stale, missing, reordered, or conflicting runtime use at index $index';
			}
		}
	}

	/** Returns the checked occurrence that prints the typed exception call. */
	public static function signalOccurrence(plan:OcamlThrowRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		return occurrenceForRole(plan, OcamlThrowRuntimeUseRole.Signal);
	}

	/** Returns one checked payload helper selected by the throw conversion. */
	public static function payloadOccurrence(plan:OcamlThrowRuntimeUsePlan, role:OcamlThrowRuntimeUseRole):OcamlRuntimeUseOccurrence {
		if (role == OcamlThrowRuntimeUseRole.Signal)
			throw 'reflaxe.ocaml [ocaml-throw:invalid-runtime-use]: throw decision "${plan.decisionId}" requested its signal as a payload helper';
		return occurrenceForRole(plan, role);
	}

	/** Returns the exact runtime modules that contain the planned private calls. */
	public static function rootModules(plan:OcamlThrowRuntimeUsePlan):Array<String> {
		final roots = new Array<String>();
		final seen:Map<String, Bool> = [];
		for (runtimeUse in plan.runtimeUseOccurrences) {
			final separator = runtimeUse.exactSymbol.indexOf(".");
			if (separator <= 0)
				throw 'reflaxe.ocaml [ocaml-throw:invalid-runtime-use]: throw decision "${plan.decisionId}" has invalid private symbol "${runtimeUse.exactSymbol}"';
			final root = runtimeUse.exactSymbol.substr(0, separator);
			if (!seen.exists(root)) {
				seen.set(root, true);
				roots.push(root);
			}
		}
		roots.sort(compareText);
		return roots;
	}

	static function occurrence(decision:OcamlControlDecision, planRevision:String, requirementId:String, role:OcamlThrowRuntimeUseRole, exactSymbol:String,
			order:Int):OcamlRuntimeUseOccurrence {
		return {
			id: runtimeUseId(decision.id, role),
			planRevision: planRevision,
			ownerId: decision.id,
			requirementId: requirementId,
			domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
			exactSymbol: exactSymbol,
			role: role,
			order: order,
			source: {
				file: decision.source.file,
				min: decision.source.min,
				max: decision.source.max
			},
			profileEligibility: decision.profileEligibility.copy(),
			cardinality: 1
		};
	}

	static function occurrenceForRole(plan:OcamlThrowRuntimeUsePlan, role:OcamlThrowRuntimeUseRole):OcamlRuntimeUseOccurrence {
		final matches = plan.runtimeUseOccurrences.filter(runtimeUse -> runtimeUse.role == role);
		if (matches.length != 1)
			throw 'reflaxe.ocaml [ocaml-throw:invalid-runtime-use]: throw decision "${plan.decisionId}" has ${matches.length} runtime uses for role "$role"';
		return copyOccurrence(matches[0]);
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);

	static function sameOccurrence(actual:OcamlRuntimeUseOccurrence, expected:OcamlRuntimeUseOccurrence):Bool {
		return actual != null
			&& actual.id == expected.id
			&& actual.planRevision == expected.planRevision
			&& actual.ownerId == expected.ownerId
			&& actual.requirementId == expected.requirementId
			&& actual.domain == expected.domain
			&& actual.exactSymbol == expected.exactSymbol
			&& actual.role == expected.role
			&& actual.order == expected.order
			&& actual.source.file == expected.source.file
			&& actual.source.min == expected.source.min
			&& actual.source.max == expected.source.max
			&& actual.profileEligibility.join(",") == expected.profileEligibility.join(",")
			&& actual.cardinality == expected.cardinality;
	}

	static function copyOccurrence(occurrence:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: occurrence.id,
			planRevision: occurrence.planRevision,
			ownerId: occurrence.ownerId,
			requirementId: occurrence.requirementId,
			domain: occurrence.domain,
			exactSymbol: occurrence.exactSymbol,
			role: occurrence.role,
			order: occurrence.order,
			source: {
				file: occurrence.source.file,
				min: occurrence.source.min,
				max: occurrence.source.max
			},
			profileEligibility: occurrence.profileEligibility.copy(),
			cardinality: occurrence.cardinality
		};
	}
}
#end
