package reflaxe.ocaml.lowered;

#if macro
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/**
	The two private runtime names selected by one complete Haxe catch chain.

	A planned catch has two distinct target-language uses: an OCaml pattern receives
	the Haxe exception signal, and an OCaml expression rethrows that signal when no
	Haxe clause matches. This record binds both uses to the same final typed catch,
	function body, and target pipeline before syntax is built.
**/
typedef OcamlCatchRuntimeUsePlan = {
	final chainId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/** Builds and checks the private-runtime ownership derived from one sealed catch chain. */
class OcamlCatchRuntimeUseContract {
	public static inline final PATTERN_ROLE = "haxe-exception-pattern";
	public static inline final RETHROW_ROLE = "unmatched-haxe-exception-rethrow";
	public static inline final PATTERN_SYMBOL = "HxRuntime.Hx_exception";
	public static inline final RETHROW_SYMBOL = "HxRuntime.hx_throw_typed";

	/** Returns the one runtime requirement shared by the catch pattern and rethrow. */
	public static function requirementId(chain:OcamlCatchChainDecision):String {
		return chain.id + ":runtime:" + chain.runtimeCapabilityId;
	}

	/** Returns the stable identity of one of the two planned target-language uses. */
	public static function runtimeUseId(chainId:String, role:String):String {
		return chainId + ":runtime-use:" + role;
	}

	/** Derives the two ordered private-runtime uses from a valid catch decision. */
	public static function forChain(chain:OcamlCatchChainDecision):OcamlCatchRuntimeUsePlan {
		OcamlControlPlan.requireCatchChain(chain);
		final binding:OcamlFunctionPlanBinding = {
			functionId: chain.functionId,
			programRevision: chain.programRevision,
			bodyRevision: chain.bodyRevision,
			pipelineRevision: chain.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final selectedRequirementId = requirementId(chain);
		final occurrences:Array<OcamlRuntimeUseOccurrence> = [
			occurrence(chain, planRevision, selectedRequirementId, PATTERN_ROLE, OcamlRuntimeUseDomain.PatternConstructor, PATTERN_SYMBOL, 0),
			occurrence(chain, planRevision, selectedRequirementId, RETHROW_ROLE, OcamlRuntimeUseDomain.ExpressionIdentifier, RETHROW_SYMBOL, 1)
		];
		return {
			chainId: chain.id,
			planRevision: planRevision,
			runtimeRequirementIds: [selectedRequirementId],
			runtimeUseOccurrences: occurrences
		};
	}

	/** Rejects a missing, stale, reordered, or conflicting catch runtime-use plan. */
	public static function requireForChain(chain:OcamlCatchChainDecision, plan:OcamlCatchRuntimeUsePlan):Void {
		final expected = forChain(chain);
		if (plan == null
			|| plan.chainId != expected.chainId
			|| plan.planRevision != expected.planRevision
			|| plan.runtimeRequirementIds.join(",") != expected.runtimeRequirementIds.join(",")
			|| plan.runtimeUseOccurrences.length != expected.runtimeUseOccurrences.length) {
			throw 'reflaxe.ocaml [ocaml-catch:invalid-runtime-use]: catch chain "${chain.id}" does not own its exact runtime requirement and occurrences';
		}
		for (index in 0...expected.runtimeUseOccurrences.length) {
			if (!sameOccurrence(plan.runtimeUseOccurrences[index], expected.runtimeUseOccurrences[index])) {
				throw 'reflaxe.ocaml [ocaml-catch:invalid-runtime-use]: catch chain "${chain.id}" has a stale, missing, reordered, or conflicting runtime use at index $index';
			}
		}
	}

	/** Returns the checked occurrence that prints the Haxe exception pattern. */
	public static function patternOccurrence(plan:OcamlCatchRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		return occurrenceForRole(plan, PATTERN_ROLE);
	}

	/** Returns the checked occurrence that prints the unmatched-signal rethrow. */
	public static function rethrowOccurrence(plan:OcamlCatchRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		return occurrenceForRole(plan, RETHROW_ROLE);
	}

	/** Returns a detached plan copy suitable for request handoff and corruption tests. */
	public static function copy(plan:OcamlCatchRuntimeUsePlan):OcamlCatchRuntimeUsePlan {
		return {
			chainId: plan.chainId,
			planRevision: plan.planRevision,
			runtimeRequirementIds: plan.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: plan.runtimeUseOccurrences.map(copyOccurrence)
		};
	}

	static function occurrence(chain:OcamlCatchChainDecision, planRevision:String, requirementId:String, role:String, domain:OcamlRuntimeUseDomain,
			exactSymbol:String, order:Int):OcamlRuntimeUseOccurrence {
		return {
			id: runtimeUseId(chain.id, role),
			planRevision: planRevision,
			ownerId: chain.id,
			requirementId: requirementId,
			domain: domain,
			exactSymbol: exactSymbol,
			role: role,
			order: order,
			source: {
				file: chain.source.file,
				min: chain.source.min,
				max: chain.source.max
			},
			profileEligibility: chain.profileEligibility.copy(),
			cardinality: 1
		};
	}

	static function occurrenceForRole(plan:OcamlCatchRuntimeUsePlan, role:String):OcamlRuntimeUseOccurrence {
		final matches = plan.runtimeUseOccurrences.filter(occurrence -> occurrence.role == role);
		if (matches.length != 1)
			throw 'reflaxe.ocaml [ocaml-catch:invalid-runtime-use]: catch chain "${plan.chainId}" has ${matches.length} runtime uses for role "$role"';
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
