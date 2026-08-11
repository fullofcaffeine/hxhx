package reflaxe.ocaml.lowered;

#if macro
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchClauseDecision;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The exact reason one catch clause tests the incoming runtime-tag list. */
enum abstract OcamlCatchRuntimeTagUseRole(String) from String to String {
	final MatchExactRuntimeTag = "match-exact-runtime-tag";
	final MatchValueException = "match-value-exception";
	final MatchAnyException = "match-any-exception";
	final ConvertAnyException = "convert-any-exception";
	final ConvertValueException = "convert-value-exception";
}

/**
	The private runtime names selected by one complete Haxe catch chain.

	The OCaml pattern receives the Haxe exception signal. Each typed clause then
	owns the exact tag tests needed by its match and payload-conversion policies.
	The final expression rethrows the signal when no clause matches. This record
	binds every use to the same final typed catch, function body, and target
	pipeline before syntax is built.
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
	public static inline final RUNTIME_TAG_SYMBOL = "HxRuntime.tags_has";
	public static inline final PRIVATE_BREAK_PATTERN_ROLE = "private-break-pattern";
	public static inline final PRIVATE_BREAK_RERAISE_ROLE = "private-break-reraise";
	public static inline final PRIVATE_CONTINUE_PATTERN_ROLE = "private-continue-pattern";
	public static inline final PRIVATE_CONTINUE_RERAISE_ROLE = "private-continue-reraise";

	/** Returns the one runtime requirement shared by the catch pattern, tag tests, and rethrow. */
	public static function requirementId(chain:OcamlCatchChainDecision):String {
		return chain.id + ":runtime:" + chain.runtimeCapabilityId;
	}

	/** Returns the stable identity of one of the two planned target-language uses. */
	public static function runtimeUseId(chainId:String, role:String):String {
		return chainId + ":runtime-use:" + role;
	}

	/** Derives every ordered private-runtime use from a valid catch decision. */
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
		final occurrences:Array<OcamlRuntimeUseOccurrence> = [];
		var order = 0;
		occurrences.push(occurrence(chain, chain.source, planRevision, selectedRequirementId, PRIVATE_BREAK_PATTERN_ROLE,
			OcamlRuntimeUseDomain.PatternConstructor, "HxRuntime.Hx_break", order++));
		occurrences.push(occurrence(chain, chain.source, planRevision, selectedRequirementId, PRIVATE_BREAK_RERAISE_ROLE,
			OcamlRuntimeUseDomain.ExpressionIdentifier, "HxRuntime.Hx_break", order++));
		occurrences.push(occurrence(chain, chain.source, planRevision, selectedRequirementId, PRIVATE_CONTINUE_PATTERN_ROLE,
			OcamlRuntimeUseDomain.PatternConstructor, "HxRuntime.Hx_continue", order++));
		occurrences.push(occurrence(chain, chain.source, planRevision, selectedRequirementId, PRIVATE_CONTINUE_RERAISE_ROLE,
			OcamlRuntimeUseDomain.ExpressionIdentifier, "HxRuntime.Hx_continue", order++));
		occurrences.push(occurrence(chain, chain.source, planRevision, selectedRequirementId, PATTERN_ROLE, OcamlRuntimeUseDomain.PatternConstructor,
			PATTERN_SYMBOL, order++));
		for (clause in chain.clauses) {
			for (role in runtimeTagRoles(clause)) {
				occurrences.push(occurrence(chain, clause.source, planRevision, selectedRequirementId, runtimeTagRole(clause.id, role),
					OcamlRuntimeUseDomain.ExpressionIdentifier, RUNTIME_TAG_SYMBOL, order++));
			}
		}
		occurrences.push(occurrence(chain, chain.source, planRevision, selectedRequirementId, RETHROW_ROLE, OcamlRuntimeUseDomain.ExpressionIdentifier,
			RETHROW_SYMBOL, order));
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

	/** Returns one checked private-control pattern or rethrow selected by the catch chain. */
	public static function privateControlOccurrence(plan:OcamlCatchRuntimeUsePlan, role:String):OcamlRuntimeUseOccurrence {
		return occurrenceForRole(plan, role);
	}

	/** Returns the one checked tag test selected for a clause role. */
	public static function runtimeTagOccurrence(plan:OcamlCatchRuntimeUsePlan, clauseId:String, role:OcamlCatchRuntimeTagUseRole):OcamlRuntimeUseOccurrence {
		return occurrenceForRole(plan, runtimeTagRole(clauseId, role));
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

	static function runtimeTagRoles(clause:OcamlCatchClauseDecision):Array<OcamlCatchRuntimeTagUseRole> {
		final roles:Array<OcamlCatchRuntimeTagUseRole> = switch (clause.matchPolicy) {
			case ExactRuntimeTag: [OcamlCatchRuntimeTagUseRole.MatchExactRuntimeTag];
			case MatchHaxeValueException: [
					OcamlCatchRuntimeTagUseRole.MatchValueException,
					OcamlCatchRuntimeTagUseRole.MatchAnyException
				];
			case MatchAll, MatchHaxeException: [];
		};
		switch (clause.conversion) {
			case PreserveOrWrapHaxeException:
				roles.push(OcamlCatchRuntimeTagUseRole.ConvertAnyException);
			case PreserveOrWrapHaxeValueException:
				roles.push(OcamlCatchRuntimeTagUseRole.ConvertValueException);
			case RecoverExactValue, RecoverCheckedBool, RecoverNominalValue, RecoverEnumValue, RecoverRuntimeClassValue, PreserveDynamicCarrier:
		}
		return roles;
	}

	static function runtimeTagRole(clauseId:String, role:OcamlCatchRuntimeTagUseRole):String {
		return 'clause:$clauseId:runtime-tag:$role';
	}

	static function occurrence(chain:OcamlCatchChainDecision, source:OcamlLoweredSourceSpan, planRevision:String, requirementId:String, role:String,
			domain:OcamlRuntimeUseDomain, exactSymbol:String, order:Int):OcamlRuntimeUseOccurrence {
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
				file: source.file,
				min: source.min,
				max: source.max
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
