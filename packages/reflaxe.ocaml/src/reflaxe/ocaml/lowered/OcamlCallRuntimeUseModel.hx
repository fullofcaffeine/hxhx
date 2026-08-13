package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultMaterialization;
import reflaxe.ocaml.lowered.OcamlStandardArrayCallModel.OcamlStandardArrayCallContract;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/**
	The private runtime calls owned by one exact typed call occurrence.

	A call argument whose Haxe type is `Bool` but whose parameter type is
	`Dynamic` needs `HxRuntime.box_bool`. This record does not give every Boolean
	conversion permission to use that helper. It binds one helper occurrence to
	the exact call, argument slot, source location, and final function revision
	that selected the conversion.
**/
typedef OcamlCallRuntimeUsePlan = {
	final callId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/** Builds and validates runtime-use ownership derived from a sealed call. */
class OcamlCallRuntimeUseContract {
	public static inline final HAXE_BOOL_CARRIER_CAPABILITY = "haxe-call-bool-carrier";
	public static inline final HAXE_ARRAY_CALL_CAPABILITY = "haxe-array";
	public static inline final HAXE_DYNAMIC_FUNCTION_CALL_CAPABILITY = "haxe-dynamic-function-call";
	public static inline final HAXE_UNTYPED_VOID_RESULT_CAPABILITY = "haxe-untyped-void-result";
	public static inline final STANDARD_ARRAY_RUNTIME_ROLE = "standard-array-operation";

	/** Returns the exact requirement identity for one Boolean argument slot. */
	public static function requirementId(callId:String, argumentIndex:Int):String {
		return '$callId:runtime:$HAXE_BOOL_CARRIER_CAPABILITY:argument:$argumentIndex';
	}

	/** Returns the exact runtime-use identity for one Boolean argument slot. */
	public static function runtimeUseId(callId:String, argumentIndex:Int):String {
		return '$callId:runtime-use:box-dynamic-bool-argument:$argumentIndex';
	}

	/** Returns the exact runtime-use identity for one standard Array operation. */
	public static function standardArrayRuntimeUseId(callId:String):String {
		return '$callId:runtime-use:standard-array-operation';
	}

	/** Returns one exact requirement identity for the Dynamic-call runtime path. */
	public static function dynamicCallRequirementId(callId:String, role:String):String {
		return '$callId:runtime:$HAXE_DYNAMIC_FUNCTION_CALL_CAPABILITY:$role';
	}

	/** Returns one exact runtime-use identity for the Dynamic-call runtime path. */
	public static function dynamicCallRuntimeUseId(callId:String, role:String):String {
		return '$callId:runtime-use:$role';
	}

	/** Returns the requirement identity for one untyped Void call result. */
	public static function untypedVoidResultRequirementId(callId:String):String {
		return '$callId:runtime:$HAXE_UNTYPED_VOID_RESULT_CAPABILITY';
	}

	/** Returns the runtime-use identity for one untyped Void call result. */
	public static function untypedVoidResultRuntimeUseId(callId:String):String {
		return '$callId:runtime-use:untyped-void-result-null';
	}

	/**
		Derives the companion plan after the ordinary typed-call contract is valid.

		Calls with no private runtime helper return `null`; an identity-only call
		therefore cannot accidentally acquire a broad runtime permission.
	**/
	public static function forCall(call:OcamlCallDecision):Null<OcamlCallRuntimeUsePlan> {
		final boxedBoolArguments = call.arguments.filter(argument -> argument.conversion == OcamlCallCarrierConversion.BoxExactBoolToDynamic);
		final standardArrayTarget = call.standardArrayTarget;
		final dynamicFunctionTarget = call.dynamicFunctionTarget;
		final materializesUntypedVoidResult = call.resultMaterialization == OcamlCallResultMaterialization.UntypedVoidAsDynamicNull;
		if (boxedBoolArguments.length == 0 && standardArrayTarget == null && dynamicFunctionTarget == null && !materializesUntypedVoidResult)
			return null;
		OcamlCallPlan.requireCall(call);
		final binding:OcamlFunctionPlanBinding = {
			functionId: call.functionId,
			programRevision: call.programRevision,
			bodyRevision: call.bodyRevision,
			pipelineRevision: call.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final requirementIds:Array<String> = [];
		final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
		if (dynamicFunctionTarget != null) {
			final roles = ["dynamic-call-argument-array-create"];
			for (index in 0...dynamicFunctionTarget.argumentSemanticTypeIds.length)
				roles.push('dynamic-call-argument-push:$index');
			roles.push("dynamic-call-invoke");
			roles.push("dynamic-call-null-receiver");
			for (role in roles) {
				final exactSymbol = if (role == "dynamic-call-argument-array-create") {
					"HxArray.create";
				} else if (role.indexOf("dynamic-call-argument-push:") == 0) {
					"HxArray.push";
				} else if (role == "dynamic-call-invoke") {
					"HxReflect.callMethod";
				} else {
					"HxRuntime.hx_null";
				}
				final selectedRequirementId = dynamicCallRequirementId(call.id, role);
				requirementIds.push(selectedRequirementId);
				occurrences.push({
					id: dynamicCallRuntimeUseId(call.id, role),
					planRevision: planRevision,
					ownerId: call.id,
					requirementId: selectedRequirementId,
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: exactSymbol,
					role: role,
					order: occurrences.length,
					source: {
						file: call.source.file,
						min: call.source.min,
						max: call.source.max
					},
					profileEligibility: call.profileEligibility.copy(),
					cardinality: 1
				});
			}
		}
		for (argument in call.arguments) {
			if (argument.conversion != OcamlCallCarrierConversion.BoxExactBoolToDynamic)
				continue;
			final selectedRequirementId = requirementId(call.id, argument.index);
			final role = 'box-dynamic-bool-argument:${argument.index}';
			requirementIds.push(selectedRequirementId);
			occurrences.push({
				id: runtimeUseId(call.id, argument.index),
				planRevision: planRevision,
				ownerId: call.id,
				requirementId: selectedRequirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: "HxRuntime.box_bool",
				role: role,
				order: occurrences.length,
				source: {
					file: call.source.file,
					min: call.source.min,
					max: call.source.max
				},
				profileEligibility: call.profileEligibility.copy(),
				cardinality: 1
			});
		}
		if (standardArrayTarget != null) {
			final selectedRequirementId = OcamlStandardArrayCallContract.runtimeRequirementId(call.id, standardArrayTarget);
			requirementIds.push(selectedRequirementId);
			occurrences.push({
				id: standardArrayRuntimeUseId(call.id),
				planRevision: planRevision,
				ownerId: call.id,
				requirementId: selectedRequirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: '${standardArrayTarget.runtimeModule}.${standardArrayTarget.runtimeFunction}',
				role: STANDARD_ARRAY_RUNTIME_ROLE,
				order: occurrences.length,
				source: {
					file: call.source.file,
					min: call.source.min,
					max: call.source.max
				},
				profileEligibility: call.profileEligibility.copy(),
				cardinality: 1
			});
		}
		if (materializesUntypedVoidResult) {
			final selectedRequirementId = untypedVoidResultRequirementId(call.id);
			requirementIds.push(selectedRequirementId);
			occurrences.push({
				id: untypedVoidResultRuntimeUseId(call.id),
				planRevision: planRevision,
				ownerId: call.id,
				requirementId: selectedRequirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: "HxRuntime.hx_null",
				role: "untyped-void-result-null",
				order: occurrences.length,
				source: {
					file: call.source.file,
					min: call.source.min,
					max: call.source.max
				},
				profileEligibility: call.profileEligibility.copy(),
				cardinality: 1
			});
		}
		return {
			callId: call.id,
			planRevision: planRevision,
			runtimeRequirementIds: requirementIds,
			runtimeUseOccurrences: occurrences
		};
	}

	/** Rejects a missing, stale, reordered, or conflicting companion plan. */
	public static function requireForCall(call:OcamlCallDecision, plan:OcamlCallRuntimeUsePlan):Void {
		final expected = forCall(call);
		if (expected == null)
			throw 'reflaxe.ocaml [ocaml-call:unexpected-runtime-use]: call "${call.id}" does not select a private runtime helper';
		if (plan == null
			|| plan.callId != expected.callId
			|| plan.planRevision != expected.planRevision
			|| plan.runtimeRequirementIds.join(",") != expected.runtimeRequirementIds.join(",")
			|| plan.runtimeUseOccurrences.length != expected.runtimeUseOccurrences.length) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-runtime-use]: call "${call.id}" does not own its exact runtime requirements and occurrences';
		}
		for (index in 0...expected.runtimeUseOccurrences.length) {
			final actualUse = plan.runtimeUseOccurrences[index];
			final expectedUse = expected.runtimeUseOccurrences[index];
			if (!sameOccurrence(actualUse, expectedUse))
				throw 'reflaxe.ocaml [ocaml-call:invalid-runtime-use]: call "${call.id}" has a stale, missing, reordered, or conflicting runtime use at index $index';
		}
	}

	/** Returns a detached copy suitable for corruption tests and request handoff. */
	public static function copy(plan:OcamlCallRuntimeUsePlan):OcamlCallRuntimeUsePlan {
		return {
			callId: plan.callId,
			planRevision: plan.planRevision,
			runtimeRequirementIds: plan.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: plan.runtimeUseOccurrences.map(copyOccurrence)
		};
	}

	/** Returns the planned occurrence for one exact argument slot. */
	public static function occurrenceForArgument(plan:OcamlCallRuntimeUsePlan, argumentIndex:Int):OcamlRuntimeUseOccurrence {
		final role = 'box-dynamic-bool-argument:$argumentIndex';
		final matches = plan.runtimeUseOccurrences.filter(occurrence -> occurrence.role == role);
		if (matches.length != 1)
			throw 'reflaxe.ocaml [ocaml-call:invalid-runtime-use]: call "${plan.callId}" has ${matches.length} runtime uses for argument $argumentIndex';
		return copyOccurrence(matches[0]);
	}

	/** Returns the one private runtime function selected by a standard Array call. */
	public static function occurrenceForStandardArray(plan:OcamlCallRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		final matches = plan.runtimeUseOccurrences.filter(occurrence -> occurrence.role == STANDARD_ARRAY_RUNTIME_ROLE);
		if (matches.length != 1)
			throw 'reflaxe.ocaml [ocaml-call:invalid-runtime-use]: call "${plan.callId}" has ${matches.length} standard Array runtime uses';
		return copyOccurrence(matches[0]);
	}

	/** Returns the one private runtime identifier selected for a Dynamic-call role. */
	public static function occurrenceForDynamicCallRole(plan:OcamlCallRuntimeUsePlan, role:String):OcamlRuntimeUseOccurrence {
		final matches = plan.runtimeUseOccurrences.filter(occurrence -> occurrence.role == role);
		if (matches.length != 1)
			throw 'reflaxe.ocaml [ocaml-call:invalid-runtime-use]: call "${plan.callId}" has ${matches.length} runtime uses for Dynamic-call role "$role"';
		return copyOccurrence(matches[0]);
	}

	/** Returns the canonical Haxe null use for one untyped Void call result. */
	public static function occurrenceForUntypedVoidResult(plan:OcamlCallRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		final matches = plan.runtimeUseOccurrences.filter(occurrence -> occurrence.role == "untyped-void-result-null");
		if (matches.length != 1)
			throw 'reflaxe.ocaml [ocaml-call:invalid-runtime-use]: call "${plan.callId}" has ${matches.length} untyped Void result runtime uses';
		return copyOccurrence(matches[0]);
	}

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
