package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/**
	Binds private Boolean helpers to one callback write and conversion role.

	Argument and result adapters use the same recursive helper inventory as generic
	calls. The owning write supplies exact source and revision identity. Syntax
	consumes these occurrences through the ordinary runtime-use authority, so a
	stored callback cannot borrow a helper permission from an unrelated call.
**/
function occurrences(decision:OcamlCallableViewLocalDecision):Array<OcamlRuntimeUseOccurrence> {
	reflaxe.ocaml.lowered.OcamlCallableViewContract.requireDecision(decision);
	final revision = OcamlRuntimeUseModel.planRevision(decision.binding);
	final result:Array<OcamlRuntimeUseOccurrence> = [];
	for (helper in reflaxe.ocaml.lowered.OcamlGenericCallConversion.runtimeHelpers(decision.conversion, "callback-write")) {
		result.push({
			id: '${decision.id}:runtime-use:${helper.role}',
			planRevision: revision,
			ownerId: decision.id,
			requirementId: '${decision.id}:runtime:${helper.role}',
			domain: ExpressionIdentifier,
			exactSymbol: helper.symbol,
			role: helper.role,
			order: result.length,
			source: {
				file: decision.source.file,
				min: decision.source.min,
				max: decision.source.max
			},
			profileEligibility: ["metal", "portable"],
			cardinality: 1
		});
	}
	return result;
}

/** Packaging receives the same exact helper inventory that syntax must consume. */
function requirements(decision:OcamlCallableViewLocalDecision):Array<OcamlRuntimeRequirement> {
	return [
		for (use in occurrences(decision))
			{
				id: use.requirementId,
				sourceKind: HaxeExpression,
				sourceId: decision.id,
				source: use.source,
				semanticCapability: "haxe-callback-bool-carrier",
				cause: LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: HaxeType,
					id: "Bool"
				},
				implementationFeature: "haxe-boolean-carrier-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: use.profileEligibility.copy(),
				explanation: "The callback write selects a Boolean argument or result adapter that preserves null and keeps Bool distinct from Int."
			}
	];
}
#end
