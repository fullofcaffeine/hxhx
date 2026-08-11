package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Private pattern uses owned by one sealed lexical loop target. */
typedef OcamlLoopTargetRuntimeUsePlan = {
	final targetId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/** The private signal raised by one sealed break or continue. */
typedef OcamlLoopTransferRuntimeUsePlan = {
	final decisionId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/**
	Binds loop-control runtime names to the typed target and transfer that own them.

	A loop target owns at most one catch pattern for each signal kind. Each source
	`break` or `continue` owns its separate raise occurrence. This distinction
	prevents several transfers from reusing one broad permission to print a private
	runtime name.
**/
class OcamlLoopRuntimeUseContract {
	public static inline final BREAK_PATTERN_ROLE = "catch-loop-break-signal";
	public static inline final CONTINUE_PATTERN_ROLE = "catch-loop-continue-signal";
	public static inline final RAISE_ROLE = "raise-loop-transfer-signal";

	/** Returns the decisions that belong to one target in stable source identity order. */
	public static function decisionsForTarget(target:OcamlControlLoopTarget, decisions:Array<OcamlControlDecision>):Array<OcamlControlDecision> {
		OcamlControlPlan.requireLoopTarget(target);
		final selected = decisions.filter(decision -> decision.targetId == target.id
			&& decision.targetKind == OcamlControlTargetKind.Loop);
		selected.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in selected)
			OcamlControlPlan.requireDecision(decision);
		return selected;
	}

	/** Derives the checked signal patterns selected by one loop target. */
	public static function forTarget(target:OcamlControlLoopTarget, decisions:Array<OcamlControlDecision>):OcamlLoopTargetRuntimeUsePlan {
		final selected = decisionsForTarget(target, decisions);
		final binding = bindingForTarget(target);
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
		final requirements:Array<String> = [];
		if (Lambda.exists(selected, decision -> decision.kind == OcamlControlTransferKind.Continue)) {
			final requirementId = targetRequirementId(target, OcamlControlTransferKind.Continue);
			requirements.push(requirementId);
			occurrences.push(patternOccurrenceValue(target, planRevision, requirementId, OcamlControlTransferKind.Continue, occurrences.length));
		}
		if (Lambda.exists(selected, decision -> decision.kind == OcamlControlTransferKind.Break)) {
			final requirementId = targetRequirementId(target, OcamlControlTransferKind.Break);
			requirements.push(requirementId);
			occurrences.push(patternOccurrenceValue(target, planRevision, requirementId, OcamlControlTransferKind.Break, occurrences.length));
		}
		return {
			targetId: target.id,
			planRevision: planRevision,
			runtimeRequirementIds: requirements,
			runtimeUseOccurrences: occurrences
		};
	}

	/** Derives the checked signal raised by one source transfer. */
	public static function forDecision(decision:OcamlControlDecision):OcamlLoopTransferRuntimeUsePlan {
		OcamlControlPlan.requireDecision(decision);
		if (decision.kind != OcamlControlTransferKind.Break && decision.kind != OcamlControlTransferKind.Continue)
			throw 'reflaxe.ocaml [ocaml-loop:unexpected-runtime-use]: control decision "${decision.id}" is not a loop transfer';
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final requirementId = transferRequirementId(decision);
		return {
			decisionId: decision.id,
			planRevision: planRevision,
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [
				{
					id: decision.id + ":runtime-use:" + RAISE_ROLE,
					planRevision: planRevision,
					ownerId: decision.id,
					requirementId: requirementId,
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: signalSymbol(decision.kind),
					role: RAISE_ROLE,
					order: 0,
					source: copySource(decision.source),
					profileEligibility: decision.profileEligibility.copy(),
					cardinality: 1
				}
			]
		};
	}

	/** Returns the target-owned pattern for one admitted signal kind. */
	public static function patternOccurrence(plan:OcamlLoopTargetRuntimeUsePlan, kind:OcamlControlTransferKind):OcamlRuntimeUseOccurrence {
		final role = patternRole(kind);
		final matches = plan.runtimeUseOccurrences.filter(occurrence -> occurrence.role == role);
		if (matches.length != 1)
			throw 'reflaxe.ocaml [ocaml-loop:invalid-runtime-use]: loop target "${plan.targetId}" has ${matches.length} occurrences for "$role"';
		return copyOccurrence(matches[0]);
	}

	/** Returns the decision-owned raise occurrence. */
	public static function signalOccurrence(plan:OcamlLoopTransferRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		if (plan.runtimeUseOccurrences.length != 1 || plan.runtimeUseOccurrences[0].role != RAISE_ROLE)
			throw 'reflaxe.ocaml [ocaml-loop:invalid-runtime-use]: transfer "${plan.decisionId}" has no unique raise occurrence';
		return copyOccurrence(plan.runtimeUseOccurrences[0]);
	}

	/** Returns the target-owned runtime requirement identity for one signal kind. */
	public static function targetRequirementId(target:OcamlControlLoopTarget, kind:OcamlControlTransferKind):String {
		return target.id + ":runtime:" + capabilityId(kind) + ":pattern";
	}

	/** Returns the transfer-owned runtime requirement identity. */
	public static function transferRequirementId(decision:OcamlControlDecision):String {
		return decision.id + ":runtime:" + decision.runtimeCapabilityId;
	}

	public static function signalSymbol(kind:OcamlControlTransferKind):String {
		return switch (kind) {
			case Break: "HxRuntime.Hx_break";
			case Continue: "HxRuntime.Hx_continue";
			case _: throw 'reflaxe.ocaml [ocaml-loop:unexpected-runtime-use]: unsupported loop signal kind $kind';
		};
	}

	public static function capabilityId(kind:OcamlControlTransferKind):String {
		return switch (kind) {
			case Break: OcamlControlPlan.BREAK_SIGNAL_CAPABILITY_ID;
			case Continue: OcamlControlPlan.CONTINUE_SIGNAL_CAPABILITY_ID;
			case _: throw 'reflaxe.ocaml [ocaml-loop:unexpected-runtime-use]: unsupported loop capability kind $kind';
		};
	}

	static function patternOccurrenceValue(target:OcamlControlLoopTarget, planRevision:String, requirementId:String, kind:OcamlControlTransferKind,
			order:Int):OcamlRuntimeUseOccurrence {
		final role = patternRole(kind);
		return {
			id: target.id + ":runtime-use:" + role,
			planRevision: planRevision,
			ownerId: target.id,
			requirementId: requirementId,
			domain: OcamlRuntimeUseDomain.PatternConstructor,
			exactSymbol: signalSymbol(kind),
			role: role,
			order: order,
			source: copySource(target.source),
			profileEligibility: ["metal", "portable"],
			cardinality: 1
		};
	}

	static function patternRole(kind:OcamlControlTransferKind):String {
		return switch (kind) {
			case Break: BREAK_PATTERN_ROLE;
			case Continue: CONTINUE_PATTERN_ROLE;
			case _: throw 'reflaxe.ocaml [ocaml-loop:unexpected-runtime-use]: unsupported loop pattern kind $kind';
		};
	}

	static function bindingForTarget(target:OcamlControlLoopTarget):OcamlFunctionPlanBinding {
		return {
			functionId: target.functionId,
			programRevision: target.programRevision,
			bodyRevision: target.bodyRevision,
			pipelineRevision: target.pipelineRevision
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
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
			source: copySource(occurrence.source),
			profileEligibility: occurrence.profileEligibility.copy(),
			cardinality: occurrence.cardinality
		};
	}
}
#end
