package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** The source-language control transfer selected before OCaml syntax. */
enum abstract OcamlControlTransferKind(String) from String to String {
	final Return = "return";
	final Break = "break";
	final Continue = "continue";
	final Throw = "throw";
}

/** The observable control effect owned by one sealed transfer. */
enum abstract OcamlControlEffect(String) from String to String {
	final ExitFunction = "exit-function";
	final ExitLoop = "exit-loop";
	final NextLoopIteration = "next-loop-iteration";
	final RaiseHaxeValue = "raise-haxe-value";
}

/** The semantic target category named by one control transfer. */
enum abstract OcamlControlTargetKind(String) from String to String {
	final Function = "function";
	final Loop = "loop";
	final HaxeExceptionChannel = "haxe-exception-channel";
}

/** Which Haxe loop form owns one lexical control target. */
enum abstract OcamlControlLoopKind(String) from String to String {
	final While = "while";
	final DoWhile = "do-while";
}

/** The target mechanism selected for an admitted control transfer. */
enum abstract OcamlControlTargetMechanism(String) from String to String {
	final RuntimeReturnSignal = "runtime-return-signal";
	final RuntimeVoidReturnSignal = "runtime-void-return-signal";
	final RuntimeBreakSignal = "runtime-break-signal";
	final RuntimeContinueSignal = "runtime-continue-signal";
	final RuntimeTypedHaxeExceptionSignal = "runtime-typed-haxe-exception-signal";
}

/** How runtime type tags supplement one sealed control transfer. */
enum abstract OcamlControlRuntimeTagPolicy(String) from String to String {
	final NoRuntimeTags = "no-runtime-tags";
	final MergeDynamicWithExactRuntimeValue = "merge-dynamic-with-exact-runtime-value";
}

/** How an exact Haxe value crosses the private runtime-control payload. */
enum abstract OcamlControlPayloadConversion(String) from String to String {
	final BoxAndRecoverExactValue = "box-and-recover-exact-value";
	final BoxAndRecoverNominalValue = "box-and-recover-nominal-value";
	final PreserveNullableCarrier = "preserve-nullable-carrier";
	final BoxExactIntToNullableCarrier = "box-exact-int-to-nullable-carrier";
	final BoxExactBoolToNullableCarrier = "box-exact-bool-to-nullable-carrier";
	final ReprAndRecoverExactValue = "repr-and-recover-exact-value";
	final BoxBoolAndRecoverExactValue = "box-bool-and-recover-exact-value";
	final PreserveNullableIntThrowCarrier = "preserve-nullable-int-throw-carrier";
	final NormalizeNullableBoolThrowCarrier = "normalize-nullable-bool-throw-carrier";
	final BoxNominalThrowCarrier = "box-nominal-throw-carrier";
	final PreserveDynamicThrowCarrier = "preserve-dynamic-throw-carrier";
	final BoxHaxeExceptionWrapperThrowCarrier = "box-haxe-exception-wrapper-throw-carrier";
}

/**
	The exact nominal layout that justifies one class-valued control payload.

	The control plan repeats this small proof reference so validation can reject
	a stale class layout before syntax construction. It does not duplicate field
	shape: the program representation registry remains the sole layout owner.
**/
typedef OcamlControlNominalRepresentationProof = {
	final targetModuleName:String;
	final targetTypeName:String;
	final layoutRevision:String;
	final representationProofId:String;
}

/** How one source catch decides whether its clause receives an exception. */
enum abstract OcamlCatchMatchPolicy(String) from String to String {
	final ExactRuntimeTag = "exact-runtime-tag";
	final MatchAll = "match-all";
	final MatchHaxeException = "match-haxe-exception";
	final MatchHaxeValueException = "match-haxe-value-exception";
}

/** How the private exception carrier becomes one typed catch variable. */
enum abstract OcamlCatchPayloadConversion(String) from String to String {
	final RecoverExactValue = "recover-exact-value";
	final RecoverCheckedBool = "recover-checked-bool";
	final RecoverNominalValue = "recover-nominal-value";
	final PreserveDynamicCarrier = "preserve-dynamic-carrier";
	final PreserveOrWrapHaxeException = "preserve-or-wrap-haxe-exception";
	final PreserveOrWrapHaxeValueException = "preserve-or-wrap-haxe-value-exception";
}

/** Runtime channels that may enter an admitted Haxe catch chain. */
enum abstract OcamlCatchInputChannel(String) from String to String {
	final HaxeExceptionSignal = "haxe-exception-signal";
	final TargetNativeException = "target-native-exception";
}

/** What an admitted catch chain does when no source clause matches. */
enum abstract OcamlCatchUnmatchedPolicy(String) from String to String {
	final RethrowHaxeExceptionSignal = "rethrow-haxe-exception-signal";
	final ReraiseTargetNativeException = "reraise-target-native-exception";
}

/** Source catches cannot intercept compiler-private non-local control. */
enum abstract OcamlCatchPrivateControlPolicy(String) from String to String {
	final PropagatePrivateControlSignals = "propagate-private-control-signals";
}

/** Observable operations owned by one admitted source catch clause. */
enum abstract OcamlCatchEffect(String) from String to String {
	final SelectFirstMatchingClause = "select-first-matching-clause";
	final BindCatchVariable = "bind-catch-variable";
	final ExecuteCatchBody = "execute-catch-body";
}

/**
	How one typed `try` branch reaches the common OCaml result type.

	A branch that can complete in a Haxe `Void` try discards its target value.
	A branch whose generated expression still ends in return/throw keeps that
	non-local expression polymorphic so an enclosing function boundary can
	recover its exact result.
**/
enum abstract OcamlCatchBranchResultPolicy(String) from String to String {
	final PreserveTypedResult = "preserve-typed-result";
	final DiscardCompletedValueToUnit = "discard-completed-value-to-unit";
}

/**
	The complete payload contract for one admitted non-local control transfer.

	The source and target sides are ordinary represented Haxe values. The signal
	carrier is private OCaml runtime plumbing and cannot become the callable's
	public result carrier. Loop transfers carry no value and therefore have no
	payload record.
**/
typedef OcamlControlPayloadPlan = {
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final inputRepresentationId:String;
	final signalCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final outputRepresentationId:String;
	final conversion:OcamlControlPayloadConversion;
	final nominalRepresentation:Null<OcamlControlNominalRepresentationProof>;
	final proofId:String;
	final proofClaim:String;
}

/**
	The represented value selected specifically for exception transport.

	Most selections refer to a program-owned representation decision. `Dynamic`
	is the one deliberate control-only case: it already arrives as `Obj.t`, so
	throwing it preserves that carrier without claiming general-purpose Dynamic
	storage, call, or public-ABI support.
**/
private typedef OcamlControlThrowRepresentation = {
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final nominalRepresentation:Null<OcamlControlNominalRepresentationProof>;
}

/** One deterministic lexical loop target owned by a sealed function body. */
typedef OcamlControlLoopTarget = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlControlLoopKind;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final proofId:String;
	final proofClaim:String;
}

/** One revision-bound control transfer owned by a Haxe function. */
typedef OcamlControlDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlControlTransferKind;
	final effect:OcamlControlEffect;
	final targetKind:OcamlControlTargetKind;
	final targetId:String;
	final payload:Null<OcamlControlPayloadPlan>;
	final runtimeTags:Array<String>;
	final runtimeTagPolicy:OcamlControlRuntimeTagPolicy;
	final mechanism:OcamlControlTargetMechanism;
	final runtimeCapabilityId:String;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	Request-local lookup from one final typed loop node to its stable target.

	The target record itself remains process-independent. Object identity is used
	only to connect the already-sealed record back to the exact immutable typed
	node consumed by syntax generation.
**/
typedef OcamlControlLoopTargetOccurrence = {
	final expression:TypedExpr;
	final targetId:String;
}

/** Request-local lookup from one final typed transfer node to its stable record. */
typedef OcamlControlDecisionOccurrence = {
	final expression:TypedExpr;
	final decisionId:String;
}

/** One ordered, typed clause within an admitted source catch chain. */
typedef OcamlCatchClauseDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final order:Int;
	final variableName:String;
	final semanticTypeId:String;
	final signalCarrierTypeId:String;
	final outputCarrierTypeId:String;
	final outputRepresentationId:String;
	final matchPolicy:OcamlCatchMatchPolicy;
	final runtimeTag:Null<String>;
	final conversion:OcamlCatchPayloadConversion;
	final nominalRepresentation:Null<OcamlControlNominalRepresentationProof>;
	final bodyResultPolicy:OcamlCatchBranchResultPolicy;
	final effects:Array<OcamlCatchEffect>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	One complete source-ordered catch chain selected before OCaml syntax.

	The record covers both the compiler-owned Haxe exception channel and
	target-native OCaml exceptions. Compiler-private return and loop signals are
	not inputs: they propagate around the source catch chain.
**/
typedef OcamlCatchChainDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final clauses:Array<OcamlCatchClauseDecision>;
	final tryBodyResultPolicy:OcamlCatchBranchResultPolicy;
	final inputChannels:Array<OcamlCatchInputChannel>;
	final targetNativeRuntimeTags:Array<String>;
	final haxeUnmatchedPolicy:OcamlCatchUnmatchedPolicy;
	final targetNativeUnmatchedPolicy:OcamlCatchUnmatchedPolicy;
	final privateControlPolicy:OcamlCatchPrivateControlPolicy;
	final runtimeCapabilityId:String;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/**
	Request-local disposition for every final typed `try` node.

	`chainId = null` records an explicit legacy disposition. The stable
	occurrence identity and source participate in the plan revision, so removing
	an admitted chain cannot silently look like intended fallback behavior.
**/
typedef OcamlCatchChainOccurrence = {
	final expression:TypedExpr;
	final occurrenceId:String;
	final source:OcamlLoweredSourceSpan;
	final chainId:Null<String>;
}

/**
	Immutable control inventory for one final function body.

	Return, loop, and throw families are admitted independently. An unsupported
	return carrier cannot discard valid loop targets, and an unsupported throw
	payload cannot discard a safe return or loop decision. Syntax may consume
	targets and decisions but cannot add or reinterpret them.
**/
class OcamlControlPlan {
	public static inline final EXACT_VALUE_RETURN_PROOF_ID = "exact-value-early-return-control-v2";
	public static inline final EXACT_NOMINAL_RETURN_PROOF_ID = "exact-monomorphic-class-early-return-control-v1";
	public static inline final NULLABLE_CARRIER_RETURN_PROOF_ID = "exact-nullable-carrier-early-return-control-v1";
	public static inline final NULLABLE_INT_CONVERSION_RETURN_PROOF_ID = "exact-int-to-nullable-early-return-control-v1";
	public static inline final NULLABLE_BOOL_CONVERSION_RETURN_PROOF_ID = "exact-bool-to-nullable-early-return-control-v1";
	public static inline final EFFECT_ONLY_VOID_RETURN_PROOF_ID = "effect-only-void-early-return-control-v1";
	public static inline final LEXICAL_LOOP_CONTROL_PROOF_ID = "lexical-loop-control-v1";
	public static inline final EXACT_VALUE_THROW_PROOF_ID = "exact-value-throw-control-v1";
	public static inline final NULLABLE_INT_THROW_PROOF_ID = "nullable-int-throw-control-v1";
	public static inline final NULLABLE_BOOL_THROW_PROOF_ID = "nullable-bool-throw-control-v1";
	public static inline final EXACT_NOMINAL_THROW_PROOF_ID = "exact-monomorphic-class-throw-control-v1";
	public static inline final DYNAMIC_THROW_PROOF_ID = "dynamic-carrier-throw-control-v1";
	public static inline final HAXE_EXCEPTION_WRAPPER_THROW_PROOF_ID = "exact-haxe-exception-wrapper-throw-control-v1";
	public static inline final REPRESENTED_VALUE_CATCH_PROOF_ID = "represented-value-catch-control-v3";
	public static inline final RETURN_SIGNAL_CAPABILITY_ID = "hxhx-runtime:function-return-signal-v1";
	public static inline final VOID_RETURN_SIGNAL_CAPABILITY_ID = "hxhx-runtime:function-void-return-signal-v1";
	public static inline final BREAK_SIGNAL_CAPABILITY_ID = "hxhx-runtime:loop-break-signal-v1";
	public static inline final CONTINUE_SIGNAL_CAPABILITY_ID = "hxhx-runtime:loop-continue-signal-v1";
	public static inline final THROW_SIGNAL_CAPABILITY_ID = "hxhx-runtime:typed-haxe-exception-signal-v1";
	public static inline final CATCH_SIGNAL_CAPABILITY_ID = "hxhx-runtime:typed-haxe-catch-chain-v1";
	public static inline final HAXE_EXCEPTION_CHANNEL_ID = "control-target:haxe-exception-channel:v1";
	public static inline final DYNAMIC_CONTROL_REPRESENTATION_ID = "control-representation:Dynamic:runtime-obj-v1";
	public static inline final HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID = "control-representation:haxe.Exception:runtime-wrapper-v1";
	public static inline final HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID = "control-representation:haxe.ValueException:runtime-wrapper-v1";

	public final returnFamilyAdmitted:Bool;
	public final loopFamilyAdmitted:Bool;
	public final throwFamilyAdmitted:Bool;
	public final binding:OcamlFunctionPlanBinding;
	public final revision:String;

	final orderedTargets:Array<OcamlControlLoopTarget>;
	final ordered:Array<OcamlControlDecision>;
	final orderedCatchChains:Array<OcamlCatchChainDecision>;
	final targetsById:Map<String, OcamlControlLoopTarget> = [];
	final decisionsById:Map<String, OcamlControlDecision> = [];
	final catchChainsById:Map<String, OcamlCatchChainDecision> = [];
	final targetsBySourceKey:Map<String, Array<OcamlControlLoopTarget>> = [];
	final bySourceKey:Map<String, Array<OcamlControlDecision>> = [];
	final catchChainsBySourceKey:Map<String, Array<OcamlCatchChainDecision>> = [];
	final targetIdByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
	final decisionIdByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
	final catchChainIdByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
	final catchDispositionByExpression:ObjectMap<TypedExpr, Bool> = new ObjectMap();
	final hasOccurrenceIndex:Bool;
	final hasCatchOccurrenceIndex:Bool;
	final catchOccurrenceFingerprints:Array<String>;

	public function new(returnFamilyAdmitted:Bool, loopFamilyAdmitted:Bool, throwFamilyAdmitted:Bool, binding:OcamlFunctionPlanBinding,
			targets:Array<OcamlControlLoopTarget>, decisions:Array<OcamlControlDecision>, ?targetOccurrences:Array<OcamlControlLoopTargetOccurrence>,
			?decisionOccurrences:Array<OcamlControlDecisionOccurrence>, ?catchChains:Array<OcamlCatchChainDecision>,
			?catchOccurrences:Array<OcamlCatchChainOccurrence>) {
		this.returnFamilyAdmitted = returnFamilyAdmitted;
		this.loopFamilyAdmitted = loopFamilyAdmitted;
		this.throwFamilyAdmitted = throwFamilyAdmitted;
		this.binding = copyBinding(binding);
		if ((targetOccurrences == null) != (decisionOccurrences == null))
			throw 'reflaxe.ocaml [ocaml-control:incomplete-occurrence-index]: loop-target and transfer occurrence indexes must be supplied together';
		hasOccurrenceIndex = targetOccurrences != null;
		hasCatchOccurrenceIndex = catchOccurrences != null;

		final sortedTargets = targets.map(copyLoopTarget);
		sortedTargets.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalizedTargets:Array<OcamlControlLoopTarget> = [];
		for (target in sortedTargets) {
			requireLoopTarget(target);
			requireTargetBinding(target, binding);
			if (!loopFamilyAdmitted)
				throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: unadmitted loop family in "${binding.functionId}" cannot own target "${target.id}"';
			if (targetsById.exists(target.id))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-target]: loop target identity "${target.id}" occurs more than once';
			final key = sourceKey(target.source);
			final candidates = targetsBySourceKey.get(key) ?? [];
			if (!hasOccurrenceIndex && candidates.length > 0)
				throw 'reflaxe.ocaml [ocaml-control:duplicate-target-source]: more than one loop target belongs to source occurrence "$key"';
			candidates.push(copyLoopTarget(target));
			targetsBySourceKey.set(key, candidates);
			targetsById.set(target.id, copyLoopTarget(target));
			normalizedTargets.push(copyLoopTarget(target));
		}
		orderedTargets = normalizedTargets;

		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalized:Array<OcamlControlDecision> = [];
		for (decision in sorted) {
			requireDecision(decision);
			requireBinding(decision, binding);
			switch (decision.kind) {
				case Return:
					if (!returnFamilyAdmitted)
						throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: unadmitted return family in "${binding.functionId}" cannot own decision "${decision.id}"';
				case Break, Continue:
					if (!loopFamilyAdmitted)
						throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: unadmitted loop family in "${binding.functionId}" cannot own decision "${decision.id}"';
					final target = targetsById.get(decision.targetId);
					if (target == null)
						throw 'reflaxe.ocaml [ocaml-control:missing-target]: loop transfer "${decision.id}" refers to missing target "${decision.targetId}"';
				case Throw:
					if (!throwFamilyAdmitted)
						throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: unadmitted throw family in "${binding.functionId}" cannot own decision "${decision.id}"';
			}
			final key = sourceKey(decision.source);
			final candidates = bySourceKey.get(key) ?? [];
			if (decisionsById.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-decision]: control identity "${decision.id}" occurs more than once in "${binding.functionId}" at "$key" for target "${decision.targetId}"';
			if (!hasOccurrenceIndex && candidates.length > 0)
				throw 'reflaxe.ocaml [ocaml-control:duplicate-source-occurrence]: more than one admitted transfer belongs to source occurrence "$key"';
			candidates.push(copyDecision(decision));
			bySourceKey.set(key, candidates);
			decisionsById.set(decision.id, copyDecision(decision));
			normalized.push(copyDecision(decision));
		}
		ordered = normalized;

		final sortedCatchChains = (catchChains ?? []).map(copyCatchChain);
		sortedCatchChains.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalizedCatchChains:Array<OcamlCatchChainDecision> = [];
		for (chain in sortedCatchChains) {
			requireCatchChain(chain);
			requireCatchBinding(chain, binding);
			if (catchChainsById.exists(chain.id))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-catch-chain]: catch-chain identity "${chain.id}" occurs more than once';
			final key = sourceKey(chain.source);
			final candidates = catchChainsBySourceKey.get(key) ?? [];
			if (!hasCatchOccurrenceIndex && candidates.length > 0)
				throw 'reflaxe.ocaml [ocaml-control:duplicate-catch-source]: more than one admitted catch chain belongs to source occurrence "$key"';
			candidates.push(copyCatchChain(chain));
			catchChainsBySourceKey.set(key, candidates);
			catchChainsById.set(chain.id, copyCatchChain(chain));
			normalizedCatchChains.push(copyCatchChain(chain));
		}
		orderedCatchChains = normalizedCatchChains;

		final indexedTargetIds:Map<String, Bool> = [];
		for (occurrence in targetOccurrences ?? []) {
			if (!targetsById.exists(occurrence.targetId))
				throw 'reflaxe.ocaml [ocaml-control:missing-target-occurrence]: typed loop occurrence refers to missing target "${occurrence.targetId}"';
			if (indexedTargetIds.exists(occurrence.targetId))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-target-occurrence]: loop target "${occurrence.targetId}" is indexed by more than one typed occurrence';
			if (targetIdByExpression.exists(occurrence.expression)
				&& targetIdByExpression.get(occurrence.expression) != occurrence.targetId) {
				throw 'reflaxe.ocaml [ocaml-control:ambiguous-target-occurrence]: one typed loop node refers to more than one stable target';
			}
			targetIdByExpression.set(occurrence.expression, occurrence.targetId);
			indexedTargetIds.set(occurrence.targetId, true);
		}
		final indexedDecisionIds:Map<String, Bool> = [];
		for (occurrence in decisionOccurrences ?? []) {
			if (!decisionsById.exists(occurrence.decisionId))
				throw 'reflaxe.ocaml [ocaml-control:missing-decision-occurrence]: typed control occurrence refers to missing decision "${occurrence.decisionId}"';
			if (indexedDecisionIds.exists(occurrence.decisionId))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-decision-occurrence]: control decision "${occurrence.decisionId}" is indexed by more than one typed occurrence';
			if (decisionIdByExpression.exists(occurrence.expression)
				&& decisionIdByExpression.get(occurrence.expression) != occurrence.decisionId) {
				throw 'reflaxe.ocaml [ocaml-control:ambiguous-decision-occurrence]: one typed control node refers to more than one stable decision';
			}
			decisionIdByExpression.set(occurrence.expression, occurrence.decisionId);
			indexedDecisionIds.set(occurrence.decisionId, true);
		}
		if (hasOccurrenceIndex) {
			for (target in orderedTargets) {
				if (!indexedTargetIds.exists(target.id))
					throw 'reflaxe.ocaml [ocaml-control:missing-target-occurrence]: loop target "${target.id}" has no exact typed occurrence';
			}
			for (decision in ordered) {
				if (!indexedDecisionIds.exists(decision.id))
					throw 'reflaxe.ocaml [ocaml-control:missing-decision-occurrence]: control decision "${decision.id}" has no exact typed occurrence';
			}
		}
		final indexedCatchChainIds:Map<String, Bool> = [];
		final indexedCatchOccurrenceIds:Map<String, Bool> = [];
		final normalizedCatchOccurrenceFingerprints:Array<String> = [];
		for (occurrence in catchOccurrences ?? []) {
			if (occurrence.occurrenceId.length == 0
				|| occurrence.source.file.length == 0
				|| occurrence.source.min < 0
				|| occurrence.source.max < occurrence.source.min) {
				throw 'reflaxe.ocaml [ocaml-control:invalid-catch-occurrence]: typed try occurrence has incomplete stable identity or source';
			}
			if (indexedCatchOccurrenceIds.exists(occurrence.occurrenceId))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-catch-occurrence]: catch occurrence "${occurrence.occurrenceId}" appears more than once';
			if (catchDispositionByExpression.exists(occurrence.expression))
				throw 'reflaxe.ocaml [ocaml-control:ambiguous-catch-occurrence]: one typed try node has more than one admitted or legacy disposition';
			if (occurrence.chainId != null) {
				if (!catchChainsById.exists(occurrence.chainId))
					throw 'reflaxe.ocaml [ocaml-control:missing-catch-occurrence]: typed try occurrence refers to missing catch chain "${occurrence.chainId}"';
				if (indexedCatchChainIds.exists(occurrence.chainId))
					throw 'reflaxe.ocaml [ocaml-control:duplicate-catch-occurrence]: catch chain "${occurrence.chainId}" is indexed by more than one typed occurrence';
				catchChainIdByExpression.set(occurrence.expression, occurrence.chainId);
				indexedCatchChainIds.set(occurrence.chainId, true);
			}
			catchDispositionByExpression.set(occurrence.expression, true);
			indexedCatchOccurrenceIds.set(occurrence.occurrenceId, true);
			normalizedCatchOccurrenceFingerprints.push([
				occurrence.occurrenceId,
				sourceKey(occurrence.source),
				occurrence.chainId ?? "legacy-catch-chain"
			].join("|"));
		}
		normalizedCatchOccurrenceFingerprints.sort(Reflect.compare);
		catchOccurrenceFingerprints = normalizedCatchOccurrenceFingerprints;
		if (hasCatchOccurrenceIndex) {
			for (chain in orderedCatchChains) {
				if (!indexedCatchChainIds.exists(chain.id))
					throw 'reflaxe.ocaml [ocaml-control:missing-catch-occurrence]: catch chain "${chain.id}" has no exact typed occurrence';
			}
		}
		revision = "sha256:" + Sha256.encode([
			returnFamilyAdmitted ? "return-admitted" : "return-legacy",
			loopFamilyAdmitted ? "loop-admitted" : "loop-legacy",
			throwFamilyAdmitted ? "throw-admitted" : "throw-legacy",
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision
		].concat(orderedTargets.map(loopTargetFingerprint))
			.concat(ordered.map(decisionFingerprint))
			.concat(orderedCatchChains.map(catchChainFingerprint))
			.concat(catchOccurrenceFingerprints)
			.join("\n"));
	}

	/** Creates an explicit empty plan for a function outside every control slice. */
	public static function notAdmitted(binding:OcamlFunctionPlanBinding):OcamlControlPlan {
		return new OcamlControlPlan(false, false, false, binding, [], []);
	}

	/** Returns immutable loop-target copies in deterministic identity order. */
	public function loopTargets():Array<OcamlControlLoopTarget> {
		return orderedTargets.map(copyLoopTarget);
	}

	/** Returns immutable transfer copies in deterministic identity order. */
	public function decisions():Array<OcamlControlDecision> {
		return ordered.map(copyDecision);
	}

	/** Returns immutable catch-chain copies in deterministic identity order. */
	public function catchChains():Array<OcamlCatchChainDecision> {
		return orderedCatchChains.map(copyCatchChain);
	}

	/** Whether syntax must install the sealed private return-signal boundary. */
	public function hasReturnTransfers():Bool {
		return Lambda.exists(ordered, decision -> decision.kind == OcamlControlTransferKind.Return);
	}

	/** Whether one loop target owns an admitted break or continue transfer. */
	public function hasTransfersForTarget(targetId:String):Bool {
		return Lambda.exists(ordered, decision -> decision.targetKind == OcamlControlTargetKind.Loop && decision.targetId == targetId);
	}

	/** Resolves one typed loop occurrence without consulting builder nesting. */
	public function loopTargetFor(expression:TypedExpr):Null<OcamlControlLoopTarget> {
		final candidates = if (hasOccurrenceIndex) {
			final targetId = targetIdByExpression.get(expression);
			final target = targetId == null ? null : targetsById.get(targetId);
			target == null ? [] : [target];
		} else {
			targetsBySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		};
		final matching = candidates.filter(target -> switch (expression.expr) {
			case TWhile(_, _, normalWhile):
				target.kind == (normalWhile ? OcamlControlLoopKind.While : OcamlControlLoopKind.DoWhile);
			case _:
				false;
		});
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-control:ambiguous-loop-target]: ${matching.length} sealed loops match one typed occurrence at ${sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))}';
		return matching.length == 0 ? null : copyLoopTarget(matching[0]);
	}

	/** Resolves one exact typed control occurrence without inventing a fallback. */
	public function decisionFor(expression:TypedExpr):Null<OcamlControlDecision> {
		final candidates = if (hasOccurrenceIndex) {
			final decisionId = decisionIdByExpression.get(expression);
			final decision = decisionId == null ? null : decisionsById.get(decisionId);
			decision == null ? [] : [decision];
		} else {
			bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		};
		final matching = candidates.filter(decision -> switch (expression.expr) {
			case TReturn(value): decision.kind == OcamlControlTransferKind.Return && ((value == null
					&& decision.payload == null
					&& decision.mechanism == OcamlControlTargetMechanism.RuntimeVoidReturnSignal)
					|| (value != null
						&& decision.payload != null
						&& decision.mechanism == OcamlControlTargetMechanism.RuntimeReturnSignal
						&& expressionMatchesPayload(value, decision.payload)));
			case TBreak: decision.kind == OcamlControlTransferKind.Break && decision.payload == null;
			case TContinue: decision.kind == OcamlControlTransferKind.Continue && decision.payload == null;
			case TThrow(value): decision.kind == OcamlControlTransferKind.Throw && decision.payload != null && expressionMatchesPayload(value,
					decision.payload);
			case _:
				false;
		});
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-control:ambiguous-source-occurrence]: ${matching.length} sealed transfers match one typed occurrence at ${sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))}';
		return matching.length == 0 ? null : copyDecision(matching[0]);
	}

	/** Resolves one exact typed `try` occurrence without reclassifying catches. */
	public function catchChainFor(expression:TypedExpr):Null<OcamlCatchChainDecision> {
		if (hasCatchOccurrenceIndex) {
			if (!catchDispositionByExpression.exists(expression))
				throw 'reflaxe.ocaml [ocaml-control:missing-catch-disposition]: typed try occurrence has no admitted or legacy catch disposition';
			final chainId = catchChainIdByExpression.get(expression);
			if (chainId == null)
				return null;
			final chain = catchChainsById.get(chainId);
			if (chain == null)
				throw 'reflaxe.ocaml [ocaml-control:missing-catch-chain]: typed try occurrence refers to missing catch chain "$chainId"';
			final matches = switch (expression.expr) {
				case TTry(_, catches): catchTypesMatchChain(catches, chain);
				case _: false;
			};
			if (!matches)
				throw 'reflaxe.ocaml [ocaml-control:stale-catch-chain]: admitted catch chain "$chainId" no longer matches its exact typed try occurrence';
			return copyCatchChain(chain);
		}
		final candidates = catchChainsBySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		final matching = candidates.filter(chain -> switch (expression.expr) {
			case TTry(_, catches): catchTypesMatchChain(catches, chain);
			case _: false;
		});
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-control:ambiguous-catch-source]: ${matching.length} sealed catch chains match one typed try at ${sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))}';
		return matching.length == 0 ? null : copyCatchChain(matching[0]);
	}

	/** Whether the planner explicitly classified this exact typed `try` node. */
	public function hasCatchDispositionFor(expression:TypedExpr):Bool {
		return hasCatchOccurrenceIndex ? catchDispositionByExpression.exists(expression) : true;
	}

	/**
		Returns one decision whose output side represents the shared function boundary.

		Different early values may use different input conversions, such as an
		exact Int and an existing Null<Int>. They are compatible only when their
		signal and output carriers, function target, and runtime mechanism match.
	**/
	public function returnBoundaryDecision():Null<OcamlControlDecision> {
		final returns = ordered.filter(decision -> decision.kind == OcamlControlTransferKind.Return);
		if (returns.length == 0)
			return null;
		final first = returns[0];
		for (decision in returns) {
			if (!sameReturnBoundary(decision.payload, first.payload)
				|| decision.targetKind != first.targetKind
				|| decision.targetId != first.targetId
				|| decision.mechanism != first.mechanism) {
				throw 'reflaxe.ocaml [ocaml-control:conflicting-return-boundary]: function "${binding.functionId}" owns incompatible early-return payloads';
			}
		}
		return copyDecision(first);
	}

	/** Checks that this plan still belongs to the exact sealed function body. */
	public function requirePlanBinding(expected:OcamlFunctionPlanBinding):Void {
		if (!sameBinding(binding, expected))
			throw 'reflaxe.ocaml [ocaml-control:stale-plan]: control plan for "${binding.functionId}" does not belong to ${expected.functionId}/${expected.bodyRevision}/${expected.pipelineRevision}';
		for (target in orderedTargets)
			requireTargetBinding(target, expected);
		for (decision in ordered)
			requireBinding(decision, expected);
		for (chain in orderedCatchChains)
			requireCatchBinding(chain, expected);
	}

	/** Validates one loop target independently for corruption and report tests. */
	public static function requireLoopTarget(target:OcamlControlLoopTarget):Void {
		if (target.id.length == 0
			|| target.source.file.length == 0
			|| target.source.min < 0
			|| target.source.max < target.source.min
			|| target.functionId.length == 0
			|| target.programRevision.length == 0
			|| target.bodyRevision.length == 0
			|| target.pipelineRevision.length == 0
			|| (target.kind != OcamlControlLoopKind.While && target.kind != OcamlControlLoopKind.DoWhile)
			|| target.proofId != LEXICAL_LOOP_CONTROL_PROOF_ID
			|| target.proofClaim.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-target]: loop target "${target.id}" has incomplete identity, source, proof, or revision';
		}
	}

	/** Validates one transfer independently for corruption and report tests. */
	public static function requireDecision(decision:OcamlControlDecision):Void {
		if (decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.targetId.length == 0
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: control decision "${decision.id}" has an incomplete identity, source, target, or revision';
		}

		switch (decision.kind) {
			case Return:
				requireReturnDecision(decision);
			case Break:
				requireLoopDecision(decision, OcamlControlEffect.ExitLoop, OcamlControlTargetMechanism.RuntimeBreakSignal, BREAK_SIGNAL_CAPABILITY_ID);
			case Continue:
				requireLoopDecision(decision, OcamlControlEffect.NextLoopIteration, OcamlControlTargetMechanism.RuntimeContinueSignal,
					CONTINUE_SIGNAL_CAPABILITY_ID);
			case Throw:
				requireThrowDecision(decision);
		}

		if (decision.profileEligibility.length != 2
			|| decision.profileEligibility[0] != "metal"
			|| decision.profileEligibility[1] != "portable"
			|| decision.reason.length == 0
			|| decision.proofClaim.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: control decision "${decision.id}" has incomplete eligibility or proof metadata';
		}
	}

	static function requireReturnDecision(decision:OcamlControlDecision):Void {
		if (decision.effect != OcamlControlEffect.ExitFunction
			|| decision.targetKind != OcamlControlTargetKind.Function
			|| decision.targetId != decision.functionId
			|| decision.runtimeTags.length != 0
			|| decision.runtimeTagPolicy != OcamlControlRuntimeTagPolicy.NoRuntimeTags) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an unsupported target, tags, or effect';
		}

		switch (decision.mechanism) {
			case RuntimeReturnSignal:
				final payload = decision.payload;
				if (decision.runtimeCapabilityId != RETURN_SIGNAL_CAPABILITY_ID
					|| payload == null
					|| payload.signalCarrierTypeId != "Obj.t"
					|| payload.proofClaim.length == 0) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an incomplete value payload crossing';
				}
				switch (payload.conversion) {
					case BoxAndRecoverExactValue:
						if (!isAdmittedExactSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)
							|| !samePayloadSides(payload)
							|| payload.nominalRepresentation != null
							|| payload.proofId != EXACT_VALUE_RETURN_PROOF_ID
							|| decision.proofId != EXACT_VALUE_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an incomplete exact-value payload crossing';
						}
					case BoxAndRecoverNominalValue:
						if (!samePayloadSides(payload)
							|| !isAdmittedNominalPayload(payload)
							|| payload.proofId != EXACT_NOMINAL_RETURN_PROOF_ID
							|| decision.proofId != EXACT_NOMINAL_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an incomplete monomorphic-class payload crossing';
						}
					case PreserveNullableCarrier:
						if (!isAdmittedNullableSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)
							|| !samePayloadSides(payload)
							|| payload.nominalRepresentation != null
							|| payload.proofId != NULLABLE_CARRIER_RETURN_PROOF_ID
							|| decision.proofId != NULLABLE_CARRIER_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid nullable-carrier payload crossing';
						}
					case BoxExactIntToNullableCarrier:
						if (!isExactNullableConversion(payload, "Int", "int", "representation:Int:internal-value", "Null<Int>",
							"representation:Null<Int>:internal-value")
							|| payload.nominalRepresentation != null
							|| payload.proofId != NULLABLE_INT_CONVERSION_RETURN_PROOF_ID
							|| decision.proofId != NULLABLE_INT_CONVERSION_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid Int-to-Null<Int> payload crossing';
						}
					case BoxExactBoolToNullableCarrier:
						if (!isExactNullableConversion(payload, "Bool", "bool", "representation:Bool:internal-value", "Null<Bool>",
							"representation:Null<Bool>:internal-value")
							|| payload.nominalRepresentation != null
							|| payload.proofId != NULLABLE_BOOL_CONVERSION_RETURN_PROOF_ID
							|| decision.proofId != NULLABLE_BOOL_CONVERSION_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid Bool-to-Null<Bool> payload crossing';
						}
					case _:
						throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" selected unsupported value conversion ${payload.conversion}';
				}
			case RuntimeVoidReturnSignal:
				if (decision.runtimeCapabilityId != VOID_RETURN_SIGNAL_CAPABILITY_ID
					|| decision.payload != null
					|| decision.proofId != EFFECT_ONLY_VOID_RETURN_PROOF_ID) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid effect-only Void contract';
				}
			case _:
				throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" selected unsupported mechanism ${decision.mechanism}';
		}
	}

	static function requireLoopDecision(decision:OcamlControlDecision, effect:OcamlControlEffect, mechanism:OcamlControlTargetMechanism,
			capabilityId:String):Void {
		if (decision.effect != effect
			|| decision.targetKind != OcamlControlTargetKind.Loop
			|| decision.payload != null
			|| decision.mechanism != mechanism
			|| decision.runtimeCapabilityId != capabilityId
			|| decision.proofId != LEXICAL_LOOP_CONTROL_PROOF_ID
			|| decision.runtimeTags.length != 0
			|| decision.runtimeTagPolicy != OcamlControlRuntimeTagPolicy.NoRuntimeTags) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: loop decision "${decision.id}" has an unsupported target, payload, effect, mechanism, or runtime capability';
		}
	}

	static function requireThrowDecision(decision:OcamlControlDecision):Void {
		final payload = decision.payload;
		if (decision.effect != OcamlControlEffect.RaiseHaxeValue
			|| decision.targetKind != OcamlControlTargetKind.HaxeExceptionChannel
			|| decision.targetId != HAXE_EXCEPTION_CHANNEL_ID
			|| decision.mechanism != OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal
			|| decision.runtimeCapabilityId != THROW_SIGNAL_CAPABILITY_ID
			|| payload == null
			|| payload.signalCarrierTypeId != "Obj.t"
			|| !samePayloadSides(payload)
			|| payload.conversion != expectedThrowConversion(payload.inputSemanticTypeId, payload.nominalRepresentation != null)
			|| payload.proofClaim.length == 0
			|| !sameStrings(decision.runtimeTags, expectedThrowTags(payload.inputSemanticTypeId, payload.nominalRepresentation != null))
			|| decision.runtimeTagPolicy != OcamlControlRuntimeTagPolicy.MergeDynamicWithExactRuntimeValue) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an unsupported exception target or incomplete value payload crossing';
		}

		final hasNominalRepresentation = payload.nominalRepresentation != null;
		final expectedProofId = expectedThrowProofId(payload.inputSemanticTypeId, hasNominalRepresentation);
		if (expectedProofId == null
			|| hasNominalRepresentation != (expectedProofId == EXACT_NOMINAL_THROW_PROOF_ID)
			|| payload.proofId != expectedProofId
			|| decision.proofId != expectedProofId) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid proof for ${payload.inputSemanticTypeId}';
		}

		switch (payload.conversion) {
			case ReprAndRecoverExactValue, BoxBoolAndRecoverExactValue:
				if (!isAdmittedExactSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an incomplete exact-value payload crossing';
				}
			case PreserveNullableIntThrowCarrier:
				if (payload.inputSemanticTypeId != "Null<Int>"
					|| !isAdmittedNullableSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid nullable-Int carrier crossing';
				}
			case NormalizeNullableBoolThrowCarrier:
				if (payload.inputSemanticTypeId != "Null<Bool>"
					|| !isAdmittedNullableSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid nullable-Bool signal normalization';
				}
			case BoxNominalThrowCarrier:
				if (!isAdmittedNominalPayload(payload)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an incomplete monomorphic-class payload crossing';
				}
			case PreserveDynamicThrowCarrier:
				if (!isAdmittedDynamicThrowPayload(payload)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid Dynamic carrier crossing';
				}
			case BoxHaxeExceptionWrapperThrowCarrier:
				if (!isAdmittedHaxeExceptionThrowPayload(payload)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid Haxe exception-wrapper carrier crossing';
				}
			case _:
				throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" selected unsupported value conversion ${payload.conversion}';
		}
	}

	/** Validates one complete ordered catch chain for reports and corruption tests. */
	public static function requireCatchChain(chain:OcamlCatchChainDecision):Void {
		if (chain.id.length == 0
			|| chain.source.file.length == 0
			|| chain.source.min < 0
			|| chain.source.max < chain.source.min
			|| chain.clauses.length == 0
			|| !isCatchBranchResultPolicy(chain.tryBodyResultPolicy)
			|| chain.functionId.length == 0
			|| chain.programRevision.length == 0
			|| chain.bodyRevision.length == 0
			|| chain.pipelineRevision.length == 0
			|| chain.inputChannels.length != 2
			|| chain.inputChannels[0] != OcamlCatchInputChannel.HaxeExceptionSignal
			|| chain.inputChannels[1] != OcamlCatchInputChannel.TargetNativeException
			|| !sameStrings(chain.targetNativeRuntimeTags, ["OcamlExn"])
			|| chain.haxeUnmatchedPolicy != OcamlCatchUnmatchedPolicy.RethrowHaxeExceptionSignal
			|| chain.targetNativeUnmatchedPolicy != OcamlCatchUnmatchedPolicy.ReraiseTargetNativeException
			|| chain.privateControlPolicy != OcamlCatchPrivateControlPolicy.PropagatePrivateControlSignals
			|| chain.runtimeCapabilityId != CATCH_SIGNAL_CAPABILITY_ID
			|| chain.profileEligibility.length != 2
			|| chain.profileEligibility[0] != "metal"
			|| chain.profileEligibility[1] != "portable"
			|| chain.reason.length == 0
			|| chain.proofId != REPRESENTED_VALUE_CATCH_PROOF_ID
			|| chain.proofClaim.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-catch-chain]: catch chain "${chain.id}" has incomplete channels, fallback behavior, proof, profile, or revision metadata';
		}

		final clauseIds:Map<String, Bool> = [];
		for (index in 0...chain.clauses.length) {
			final clause = chain.clauses[index];
			requireCatchClause(clause);
			if (clauseIds.exists(clause.id))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-catch-clause]: catch chain "${chain.id}" repeats clause identity "${clause.id}"';
			if (clause.order != index)
				throw 'reflaxe.ocaml [ocaml-control:invalid-catch-order]: catch chain "${chain.id}" expected clause order $index, got ${clause.order}';
			if (clause.functionId != chain.functionId
				|| clause.programRevision != chain.programRevision
				|| clause.bodyRevision != chain.bodyRevision
				|| clause.pipelineRevision != chain.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-control:stale-catch-clause]: catch clause "${clause.id}" does not belong to chain "${chain.id}"';
			}
			if (clause.matchPolicy == OcamlCatchMatchPolicy.MatchAll && index != chain.clauses.length - 1)
				throw 'reflaxe.ocaml [ocaml-control:invalid-catch-order]: Dynamic catch clause "${clause.id}" must be the final source clause';
			clauseIds.set(clause.id, true);
		}
	}

	/** Validates one clause without consulting generated target syntax. */
	public static function requireCatchClause(clause:OcamlCatchClauseDecision):Void {
		if (clause.id.length == 0
			|| clause.source.file.length == 0
			|| clause.source.min < 0
			|| clause.source.max < clause.source.min
			|| clause.order < 0
			|| clause.variableName.length == 0
			|| clause.signalCarrierTypeId != "Obj.t"
			|| !isCatchBranchResultPolicy(clause.bodyResultPolicy)
			|| clause.effects.length != 3
			|| clause.effects[0] != OcamlCatchEffect.SelectFirstMatchingClause
			|| clause.effects[1] != OcamlCatchEffect.BindCatchVariable
			|| clause.effects[2] != OcamlCatchEffect.ExecuteCatchBody
			|| clause.proofId != REPRESENTED_VALUE_CATCH_PROOF_ID
			|| clause.proofClaim.length == 0
			|| clause.functionId.length == 0
			|| clause.programRevision.length == 0
			|| clause.bodyRevision.length == 0
			|| clause.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: catch clause "${clause.id}" has incomplete identity, payload, effects, proof, or revision metadata';
		}

		switch (clause.semanticTypeId) {
			case "Int":
				requireExactCatchSide(clause, "int", "representation:Int:internal-value", "Int", OcamlCatchPayloadConversion.RecoverExactValue);
			case "Bool":
				requireExactCatchSide(clause, "bool", "representation:Bool:internal-value", "Bool", OcamlCatchPayloadConversion.RecoverCheckedBool);
			case "String":
				requireExactCatchSide(clause, "string", "representation:String:internal-value", "String", OcamlCatchPayloadConversion.RecoverExactValue);
			case _ if (clause.nominalRepresentation != null):
				if (!isAdmittedNominalCatchClause(clause)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: nominal catch clause "${clause.id}" has an invalid tag, carrier, representation, conversion, or layout proof';
				}
			case "Dynamic":
				if (clause.outputCarrierTypeId != "Obj.t"
					|| clause.outputRepresentationId != DYNAMIC_CONTROL_REPRESENTATION_ID
					|| clause.matchPolicy != OcamlCatchMatchPolicy.MatchAll
					|| clause.runtimeTag != null
					|| clause.conversion != OcamlCatchPayloadConversion.PreserveDynamicCarrier
					|| clause.nominalRepresentation != null) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: Dynamic catch clause "${clause.id}" has an invalid match-all or carrier-preserving contract';
				}
			case "haxe.Exception", "haxe.ValueException":
				if (!isAdmittedHaxeExceptionCatchClause(clause)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: Haxe exception wrapper clause "${clause.id}" has an invalid match, carrier, representation, or wrapping contract';
				}
			case _:
				throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: catch clause "${clause.id}" has unsupported semantic type "${clause.semanticTypeId}"';
		}
	}

	static function isCatchBranchResultPolicy(policy:OcamlCatchBranchResultPolicy):Bool {
		return policy == OcamlCatchBranchResultPolicy.PreserveTypedResult
			|| policy == OcamlCatchBranchResultPolicy.DiscardCompletedValueToUnit;
	}

	static function requireExactCatchSide(clause:OcamlCatchClauseDecision, carrierTypeId:String, representationId:String, runtimeTag:String,
			conversion:OcamlCatchPayloadConversion):Void {
		if (clause.outputCarrierTypeId != carrierTypeId
			|| clause.outputRepresentationId != representationId
			|| clause.matchPolicy != OcamlCatchMatchPolicy.ExactRuntimeTag
			|| clause.runtimeTag != runtimeTag
			|| clause.conversion != conversion
			|| clause.nominalRepresentation != null) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: exact ${clause.semanticTypeId} catch clause "${clause.id}" has an invalid tag, carrier, representation, or conversion';
		}
	}

	public static function copyLoopTarget(target:OcamlControlLoopTarget):OcamlControlLoopTarget {
		return {
			id: target.id,
			source: {
				file: target.source.file,
				min: target.source.min,
				max: target.source.max
			},
			kind: target.kind,
			functionId: target.functionId,
			programRevision: target.programRevision,
			bodyRevision: target.bodyRevision,
			pipelineRevision: target.pipelineRevision,
			proofId: target.proofId,
			proofClaim: target.proofClaim
		};
	}

	public static function copyDecision(decision:OcamlControlDecision):OcamlControlDecision {
		return {
			id: decision.id,
			source: {
				file: decision.source.file,
				min: decision.source.min,
				max: decision.source.max
			},
			kind: decision.kind,
			effect: decision.effect,
			targetKind: decision.targetKind,
			targetId: decision.targetId,
			payload: copyPayload(decision.payload),
			runtimeTags: decision.runtimeTags.copy(),
			runtimeTagPolicy: decision.runtimeTagPolicy,
			mechanism: decision.mechanism,
			runtimeCapabilityId: decision.runtimeCapabilityId,
			profileEligibility: decision.profileEligibility.copy(),
			reason: decision.reason,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	public static function copyCatchChain(chain:OcamlCatchChainDecision):OcamlCatchChainDecision {
		return {
			id: chain.id,
			source: {
				file: chain.source.file,
				min: chain.source.min,
				max: chain.source.max
			},
			clauses: chain.clauses.map(copyCatchClause),
			tryBodyResultPolicy: chain.tryBodyResultPolicy,
			inputChannels: chain.inputChannels.copy(),
			targetNativeRuntimeTags: chain.targetNativeRuntimeTags.copy(),
			haxeUnmatchedPolicy: chain.haxeUnmatchedPolicy,
			targetNativeUnmatchedPolicy: chain.targetNativeUnmatchedPolicy,
			privateControlPolicy: chain.privateControlPolicy,
			runtimeCapabilityId: chain.runtimeCapabilityId,
			profileEligibility: chain.profileEligibility.copy(),
			reason: chain.reason,
			proofId: chain.proofId,
			proofClaim: chain.proofClaim,
			functionId: chain.functionId,
			programRevision: chain.programRevision,
			bodyRevision: chain.bodyRevision,
			pipelineRevision: chain.pipelineRevision
		};
	}

	public static function copyCatchClause(clause:OcamlCatchClauseDecision):OcamlCatchClauseDecision {
		return {
			id: clause.id,
			source: {
				file: clause.source.file,
				min: clause.source.min,
				max: clause.source.max
			},
			order: clause.order,
			variableName: clause.variableName,
			semanticTypeId: clause.semanticTypeId,
			signalCarrierTypeId: clause.signalCarrierTypeId,
			outputCarrierTypeId: clause.outputCarrierTypeId,
			outputRepresentationId: clause.outputRepresentationId,
			matchPolicy: clause.matchPolicy,
			runtimeTag: clause.runtimeTag,
			conversion: clause.conversion,
			nominalRepresentation: copyNominalRepresentation(clause.nominalRepresentation),
			bodyResultPolicy: clause.bodyResultPolicy,
			effects: clause.effects.copy(),
			proofId: clause.proofId,
			proofClaim: clause.proofClaim,
			functionId: clause.functionId,
			programRevision: clause.programRevision,
			bodyRevision: clause.bodyRevision,
			pipelineRevision: clause.pipelineRevision
		};
	}

	static function copyPayload(payload:Null<OcamlControlPayloadPlan>):Null<OcamlControlPayloadPlan> {
		if (payload == null)
			return null;
		return {
			inputSemanticTypeId: payload.inputSemanticTypeId,
			inputCarrierTypeId: payload.inputCarrierTypeId,
			inputRepresentationId: payload.inputRepresentationId,
			signalCarrierTypeId: payload.signalCarrierTypeId,
			outputSemanticTypeId: payload.outputSemanticTypeId,
			outputCarrierTypeId: payload.outputCarrierTypeId,
			outputRepresentationId: payload.outputRepresentationId,
			conversion: payload.conversion,
			nominalRepresentation: copyNominalRepresentation(payload.nominalRepresentation),
			proofId: payload.proofId,
			proofClaim: payload.proofClaim
		};
	}

	static function copyNominalRepresentation(proof:Null<OcamlControlNominalRepresentationProof>):Null<OcamlControlNominalRepresentationProof> {
		if (proof == null)
			return null;
		return {
			targetModuleName: proof.targetModuleName,
			targetTypeName: proof.targetTypeName,
			layoutRevision: proof.layoutRevision,
			representationProofId: proof.representationProofId
		};
	}

	static function requireTargetBinding(target:OcamlControlLoopTarget, binding:OcamlFunctionPlanBinding):Void {
		if (target.functionId != binding.functionId
			|| target.programRevision != binding.programRevision
			|| target.bodyRevision != binding.bodyRevision
			|| target.pipelineRevision != binding.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-control:stale-target]: loop target "${target.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
		}
	}

	static function requireBinding(decision:OcamlControlDecision, binding:OcamlFunctionPlanBinding):Void {
		if (decision.functionId != binding.functionId
			|| decision.programRevision != binding.programRevision
			|| decision.bodyRevision != binding.bodyRevision
			|| decision.pipelineRevision != binding.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-control:stale-binding]: control decision "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
		}
	}

	static function requireCatchBinding(chain:OcamlCatchChainDecision, binding:OcamlFunctionPlanBinding):Void {
		if (chain.functionId != binding.functionId
			|| chain.programRevision != binding.programRevision
			|| chain.bodyRevision != binding.bodyRevision
			|| chain.pipelineRevision != binding.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-control:stale-catch-chain]: catch chain "${chain.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
		}
	}

	static function sameBinding(left:OcamlFunctionPlanBinding, right:OcamlFunctionPlanBinding):Bool {
		return left.functionId == right.functionId
			&& left.programRevision == right.programRevision
			&& left.bodyRevision == right.bodyRevision
			&& left.pipelineRevision == right.pipelineRevision;
	}

	static function copyBinding(binding:OcamlFunctionPlanBinding):OcamlFunctionPlanBinding {
		return {
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	/** Whether one semantic/carrier/representation side belongs to this slice. */
	public static function isAdmittedExactSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return (semanticTypeId == "Int" && carrierTypeId == "int" && representationId == "representation:Int:internal-value")
			|| (semanticTypeId == "Bool" && carrierTypeId == "bool" && representationId == "representation:Bool:internal-value")
			|| (semanticTypeId == "String" && carrierTypeId == "string" && representationId == "representation:String:internal-value");
	}

	/** Whether one control payload side is an exact nullable primitive `Obj.t` carrier. */
	public static function isAdmittedNullableSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return (semanticTypeId == "Null<Int>" && carrierTypeId == "Obj.t" && representationId == "representation:Null<Int>:internal-value")
			|| (semanticTypeId == "Null<Bool>"
				&& carrierTypeId == "Obj.t"
				&& representationId == "representation:Null<Bool>:internal-value");
	}

	static function samePayloadSides(payload:OcamlControlPayloadPlan):Bool {
		return payload.outputSemanticTypeId == payload.inputSemanticTypeId
			&& payload.outputCarrierTypeId == payload.inputCarrierTypeId
			&& payload.outputRepresentationId == payload.inputRepresentationId;
	}

	static function isExactNullableConversion(payload:OcamlControlPayloadPlan, inputSemanticTypeId:String, inputCarrierTypeId:String,
			inputRepresentationId:String, outputSemanticTypeId:String, outputRepresentationId:String):Bool {
		return payload.inputSemanticTypeId == inputSemanticTypeId
			&& payload.inputCarrierTypeId == inputCarrierTypeId
			&& payload.inputRepresentationId == inputRepresentationId
			&& payload.signalCarrierTypeId == "Obj.t"
			&& payload.outputSemanticTypeId == outputSemanticTypeId
			&& payload.outputCarrierTypeId == "Obj.t"
			&& payload.outputRepresentationId == outputRepresentationId;
	}

	static function isAdmittedNominalPayload(payload:OcamlControlPayloadPlan):Bool {
		final nominal = payload.nominalRepresentation;
		if (nominal == null)
			return false;
		final expectedRepresentationId = 'representation:${payload.inputSemanticTypeId}:internal-value';
		return payload.inputSemanticTypeId.length > 0
			&& payload.inputCarrierTypeId == nominal.targetTypeName
			&& payload.inputRepresentationId == expectedRepresentationId
			&& nominal.targetModuleName.length > 0
			&& nominal.targetTypeName.length > 0
			&& isSha256Revision(nominal.layoutRevision)
			&& nominal.representationProofId == "whole-program-monomorphic-nominal-record-v1:" + nominal.layoutRevision;
	}

	static function isAdmittedNominalCatchClause(clause:OcamlCatchClauseDecision):Bool {
		final nominal = clause.nominalRepresentation;
		if (nominal == null)
			return false;
		return clause.semanticTypeId.length > 0
			&& clause.outputCarrierTypeId == nominal.targetTypeName
			&& clause.outputRepresentationId == 'representation:${clause.semanticTypeId}:internal-value'
			&& clause.matchPolicy == OcamlCatchMatchPolicy.ExactRuntimeTag
			&& clause.runtimeTag == clause.semanticTypeId
			&& clause.conversion == OcamlCatchPayloadConversion.RecoverNominalValue
			&& nominal.targetModuleName.length > 0
			&& nominal.targetTypeName.length > 0
			&& isSha256Revision(nominal.layoutRevision)
			&& nominal.representationProofId == "whole-program-monomorphic-nominal-record-v1:" + nominal.layoutRevision;
	}

	/**
		Reports whether one catch-only Haxe exception wrapper contract is exact.

		These two generated Haxe runtime classes are not general program
		representation decisions. The control plan records only how a source catch
		matches and binds the private exception carrier.
	**/
	public static function isAdmittedHaxeExceptionCatchClause(clause:OcamlCatchClauseDecision):Bool {
		if (clause.runtimeTag != null || clause.nominalRepresentation != null)
			return false;
		return switch (clause.semanticTypeId) {
			case "haxe.Exception":
				clause.outputCarrierTypeId == "Haxe_Exception.t"
				&& clause.outputRepresentationId == HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID
				&& clause.matchPolicy == OcamlCatchMatchPolicy.MatchHaxeException
				&& clause.conversion == OcamlCatchPayloadConversion.PreserveOrWrapHaxeException;
			case "haxe.ValueException":
				clause.outputCarrierTypeId == "Haxe_ValueException.t"
				&& clause.outputRepresentationId == HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID
				&& clause.matchPolicy == OcamlCatchMatchPolicy.MatchHaxeValueException
				&& clause.conversion == OcamlCatchPayloadConversion.PreserveOrWrapHaxeValueException;
			case _:
				false;
		}
	}

	static function isSha256Revision(value:String):Bool {
		return ~/^sha256:[0-9a-f]{64}$/.match(value);
	}

	public static function expectedThrowTags(semanticTypeId:String, hasNominalRepresentation:Bool = false):Array<String> {
		return switch (semanticTypeId) {
			case "Int", "Bool", "String", "Null<Int>", "Null<Bool>", "Dynamic", "haxe.Exception", "haxe.ValueException": ["Dynamic"];
			case _: hasNominalRepresentation ? ["Dynamic"] : [];
		}
	}

	public static function expectedThrowConversion(semanticTypeId:String, hasNominalRepresentation:Bool = false):Null<OcamlControlPayloadConversion> {
		return switch (semanticTypeId) {
			case "Int", "String": OcamlControlPayloadConversion.ReprAndRecoverExactValue;
			case "Bool": OcamlControlPayloadConversion.BoxBoolAndRecoverExactValue;
			case "Null<Int>": OcamlControlPayloadConversion.PreserveNullableIntThrowCarrier;
			case "Null<Bool>": OcamlControlPayloadConversion.NormalizeNullableBoolThrowCarrier;
			case "Dynamic": OcamlControlPayloadConversion.PreserveDynamicThrowCarrier;
			case "haxe.Exception", "haxe.ValueException": OcamlControlPayloadConversion.BoxHaxeExceptionWrapperThrowCarrier;
			case _: hasNominalRepresentation ? OcamlControlPayloadConversion.BoxNominalThrowCarrier : null;
		}
	}

	/** Selects the proof family required by one admitted throw payload. */
	public static function expectedThrowProofId(semanticTypeId:String, hasNominalRepresentation:Bool = false):Null<String> {
		return switch (semanticTypeId) {
			case "Int", "Bool", "String": EXACT_VALUE_THROW_PROOF_ID;
			case "Null<Int>": NULLABLE_INT_THROW_PROOF_ID;
			case "Null<Bool>": NULLABLE_BOOL_THROW_PROOF_ID;
			case "Dynamic": DYNAMIC_THROW_PROOF_ID;
			case "haxe.Exception", "haxe.ValueException": HAXE_EXCEPTION_WRAPPER_THROW_PROOF_ID;
			case _: hasNominalRepresentation ? EXACT_NOMINAL_THROW_PROOF_ID : null;
		}
	}

	/**
		Reports whether one throw payload preserves the compiler-owned Dynamic
		exception carrier without claiming a reusable program representation.

		The caller must still validate the surrounding throw decision. This
		predicate owns only the exceptional Dynamic payload boundary shared by
		the plan, sealer, and lowering-report writer.
	**/
	public static function isAdmittedDynamicThrowPayload(payload:OcamlControlPayloadPlan):Bool {
		return payload.inputSemanticTypeId == "Dynamic"
			&& payload.inputCarrierTypeId == "Obj.t"
			&& payload.inputRepresentationId == DYNAMIC_CONTROL_REPRESENTATION_ID
			&& payload.outputSemanticTypeId == "Dynamic"
			&& payload.outputCarrierTypeId == "Obj.t"
			&& payload.outputRepresentationId == DYNAMIC_CONTROL_REPRESENTATION_ID
			&& payload.conversion == OcamlControlPayloadConversion.PreserveDynamicThrowCarrier
			&& payload.nominalRepresentation == null;
	}

	/**
		Reports whether an exact generated Haxe exception wrapper crosses the
		private exception channel without changing object identity.

		This is a control-only contract. It intentionally does not claim that the
		program representation registry owns general Exception class layouts or
		subclass recovery.
	**/
	public static function isAdmittedHaxeExceptionThrowPayload(payload:OcamlControlPayloadPlan):Bool {
		if (payload.nominalRepresentation != null
			|| payload.signalCarrierTypeId != "Obj.t"
			|| payload.conversion != OcamlControlPayloadConversion.BoxHaxeExceptionWrapperThrowCarrier
			|| !samePayloadSides(payload)) {
			return false;
		}
		return switch (payload.inputSemanticTypeId) {
			case "haxe.Exception": payload.inputCarrierTypeId == "Haxe_Exception.t" && payload.inputRepresentationId == HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID;
			case "haxe.ValueException": payload.inputCarrierTypeId == "Haxe_ValueException.t" && payload.inputRepresentationId == HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID;
			case _:
				false;
		}
	}

	static function sameStrings(left:Array<String>, right:Array<String>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length)
			if (left[index] != right[index])
				return false;
		return true;
	}

	static function expressionMatchesPayload(expression:TypedExpr, payload:OcamlControlPayloadPlan):Bool {
		return switch (payload.inputSemanticTypeId) {
			case "Int": OcamlRepresentationRegistry.isExactInt(expression.t);
			case "Bool": OcamlRepresentationRegistry.isExactBool(expression.t);
			case "Null<Int>": OcamlRepresentationRegistry.isExactNullInt(expression.t);
			case "Null<Bool>": OcamlRepresentationRegistry.isExactNullBool(expression.t);
			case "String": OcamlRepresentationRegistry.isExactString(expression.t);
			case "Dynamic":
				switch (haxe.macro.TypeTools.follow(expression.t)) {
					case TDynamic(_): payload.inputCarrierTypeId == "Obj.t" && payload.inputRepresentationId == DYNAMIC_CONTROL_REPRESENTATION_ID && payload.conversion == OcamlControlPayloadConversion.PreserveDynamicThrowCarrier;
					case _:
						false;
				}
			case "haxe.Exception",
				"haxe.ValueException": haxeExceptionWrapperTypeId(expression.t) == payload.inputSemanticTypeId && isAdmittedHaxeExceptionThrowPayload(payload);
			case _: final semanticTypeId = OcamlRepresentationRegistry.monomorphicClassSemanticTypeId(expression.t); (payload.conversion == OcamlControlPayloadConversion.BoxAndRecoverNominalValue
					|| payload.conversion == OcamlControlPayloadConversion.BoxNominalThrowCarrier) && semanticTypeId == payload.inputSemanticTypeId && isAdmittedNominalPayload(payload);
		}
	}

	/** Returns the exact generated Haxe exception runtime class, if any. */
	public static function haxeExceptionWrapperTypeId(type:Type):Null<String> {
		return switch (haxe.macro.TypeTools.follow(type)) {
			case TInst(classRef, _):
				final classType = classRef.get();
				final pack = classType.pack ?? [];
				if (pack.length == 1 && pack[0] == "haxe" && (classType.name == "Exception" || classType.name == "ValueException")) {
					"haxe." + classType.name;
				} else {
					null;
				}
			case _:
				null;
		}
	}

	static function catchTypesMatchChain(catches:Array<{v:TVar, expr:TypedExpr}>, chain:OcamlCatchChainDecision):Bool {
		if (catches.length != chain.clauses.length)
			return false;
		for (index in 0...catches.length) {
			final entry = catches[index];
			final clause = chain.clauses[index];
			if (entry.v.name != clause.variableName || !catchTypeMatchesClause(entry.v.t, clause))
				return false;
		}
		return true;
	}

	static function catchTypeMatchesClause(type:Type, clause:OcamlCatchClauseDecision):Bool {
		return switch (clause.semanticTypeId) {
			case "Int": OcamlRepresentationRegistry.isExactInt(type);
			case "Bool": OcamlRepresentationRegistry.isExactBool(type);
			case "String": OcamlRepresentationRegistry.isExactString(type);
			case "Dynamic":
				switch (haxe.macro.TypeTools.follow(type)) {
					case TDynamic(_): true;
					case _: false;
				}
			case "haxe.Exception",
				"haxe.ValueException": haxeExceptionWrapperTypeId(type) == clause.semanticTypeId && isAdmittedHaxeExceptionCatchClause(clause);
			case _: final semanticTypeId = OcamlRepresentationRegistry.monomorphicClassSemanticTypeId(type); semanticTypeId != null && semanticTypeId == clause.semanticTypeId && isAdmittedNominalCatchClause(clause);
		}
	}

	static function payloadFingerprint(payload:Null<OcamlControlPayloadPlan>):String {
		if (payload == null)
			return "no-payload";
		return [
			payload.inputSemanticTypeId,
			payload.inputCarrierTypeId,
			payload.inputRepresentationId,
			payload.signalCarrierTypeId,
			payload.outputSemanticTypeId,
			payload.outputCarrierTypeId,
			payload.outputRepresentationId,
			(payload.conversion : String),
			nominalPayloadFingerprint(payload.nominalRepresentation),
			payload.proofId,
			payload.proofClaim
		].join("|");
	}

	static function nominalPayloadFingerprint(proof:Null<OcamlControlNominalRepresentationProof>):String {
		return proof == null ? "no-nominal-representation" : [
			proof.targetModuleName,
			proof.targetTypeName,
			proof.layoutRevision,
			proof.representationProofId
		].join("|");
	}

	static function sameReturnBoundary(left:Null<OcamlControlPayloadPlan>, right:Null<OcamlControlPayloadPlan>):Bool {
		if (left == null || right == null)
			return left == null && right == null;
		return left.signalCarrierTypeId == right.signalCarrierTypeId
			&& left.outputSemanticTypeId == right.outputSemanticTypeId
			&& left.outputCarrierTypeId == right.outputCarrierTypeId
			&& left.outputRepresentationId == right.outputRepresentationId;
	}

	static function loopTargetFingerprint(target:OcamlControlLoopTarget):String {
		return [
			target.id,
			sourceKey(target.source),
			(target.kind : String),
			target.functionId,
			target.programRevision,
			target.bodyRevision,
			target.pipelineRevision,
			target.proofId,
			target.proofClaim
		].join("|");
	}

	static function decisionFingerprint(decision:OcamlControlDecision):String {
		return [
			decision.id,
			sourceKey(decision.source),
			(decision.kind : String),
			(decision.effect : String),
			(decision.targetKind : String),
			decision.targetId,
			payloadFingerprint(decision.payload),
			decision.runtimeTags.join(","),
			(decision.runtimeTagPolicy : String),
			(decision.mechanism : String),
			decision.runtimeCapabilityId,
			decision.profileEligibility.join(","),
			decision.reason,
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function catchClauseFingerprint(clause:OcamlCatchClauseDecision):String {
		return [
			clause.id,
			sourceKey(clause.source),
			Std.string(clause.order),
			clause.variableName,
			clause.semanticTypeId,
			clause.signalCarrierTypeId,
			clause.outputCarrierTypeId,
			clause.outputRepresentationId,
			(clause.matchPolicy : String),
			clause.runtimeTag ?? "no-runtime-tag",
			(clause.conversion : String),
			nominalPayloadFingerprint(clause.nominalRepresentation),
			(clause.bodyResultPolicy : String),
			clause.effects.join(","),
			clause.proofId,
			clause.proofClaim,
			clause.functionId,
			clause.programRevision,
			clause.bodyRevision,
			clause.pipelineRevision
		].join("|");
	}

	static function catchChainFingerprint(chain:OcamlCatchChainDecision):String {
		return [
			chain.id,
			sourceKey(chain.source),
			(chain.tryBodyResultPolicy : String),
			chain.inputChannels.join(","),
			chain.targetNativeRuntimeTags.join(","),
			(chain.haxeUnmatchedPolicy : String),
			(chain.targetNativeUnmatchedPolicy : String),
			(chain.privateControlPolicy : String),
			chain.runtimeCapabilityId,
			chain.profileEligibility.join(","),
			chain.reason,
			chain.proofId,
			chain.proofClaim,
			chain.functionId,
			chain.programRevision,
			chain.bodyRevision,
			chain.pipelineRevision
		].concat(chain.clauses.map(catchClauseFingerprint)).join("|");
	}
}

/**
	Selects exact-value or effect-only `Void` returns, represented primitive or
	monomorphic-class throws, lexical loop transfers, and represented
	primitive/monomorphic-class/Dynamic catch chains.

	Return-family admission depends on the callable result carrier. Loop-family
	admission is independent and records `while`/`do ... while` targets in every
	sealed function body. Throw-family admission is independent and accepts exact
	`Int`, `Bool`, represented `String`, `Null<Int>`, `Null<Bool>`, and one exact
	whole-program-monomorphic class payload. Nested function literals own
	independent boundaries and are deliberately skipped. Each source `try` is
	admitted independently, so one unsupported catch chain does not discard
	another represented chain in the same function.

	Stable record IDs use the node's structural path through the final typed body,
	not its source span. Haxe-generated nodes can legitimately share `(unknown):0`
	or another copied position; source spans remain diagnostics, while a private
	request-local object index reconnects each stable record to the exact immutable
	node consumed by syntax generation.
**/
class OcamlControlPlanner {
	final representations:OcamlRepresentationRegistry;
	final localRepresentations:OcamlLocalRepresentationPlan;
	final binding:OcamlFunctionPlanBinding;
	final nominalCatchRepresentations:Map<Int, OcamlRepresentationDecision> = [];

	public function new(representations:OcamlRepresentationRegistry, localRepresentations:OcamlLocalRepresentationPlan, binding:OcamlFunctionPlanBinding) {
		this.representations = representations;
		this.localRepresentations = localRepresentations;
		this.binding = binding;
	}

	public function plan(body:Null<TypedExpr>, boundary:Null<OcamlCallableBoundaryPlan>):OcamlControlPlan {
		if (body == null)
			return OcamlControlPlan.notAdmitted(binding);

		final boundaryPayload = admittedBoundaryPayload(boundary);
		final effectOnlyVoidBoundary = admittedEffectOnlyVoidBoundary(boundary);
		var returnFamilyAdmitted = boundaryPayload != null || effectOnlyVoidBoundary;
		var loopFamilyAdmitted = true;
		var throwFamilyAdmitted = true;
		final targets:Array<OcamlControlLoopTarget> = [];
		var decisions:Array<OcamlControlDecision> = [];
		final catchChains:Array<OcamlCatchChainDecision> = [];
		final targetOccurrences:Array<OcamlControlLoopTargetOccurrence> = [];
		var decisionOccurrences:Array<OcamlControlDecisionOccurrence> = [];
		final catchOccurrences:Array<OcamlCatchChainOccurrence> = [];
		final loopStack:Array<OcamlControlLoopTarget> = [];

		function addLoopTransfer(expression:TypedExpr, path:String, kind:OcamlControlTransferKind):Void {
			if (loopStack.length == 0) {
				loopFamilyAdmitted = false;
				return;
			}
			final target = loopStack[loopStack.length - 1];
			final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
			final isBreak = kind == OcamlControlTransferKind.Break;
			final proofClaim = 'The final typed Haxe body binds this $kind to lexical ${target.kind} target "${target.id}" in the same function. The private runtime signal is caught only by the mechanically matched innermost loop boundary.';
			final decision:OcamlControlDecision = {
				id: controlId(kind, path, target.id),
				source: source,
				kind: kind,
				effect: isBreak ? OcamlControlEffect.ExitLoop : OcamlControlEffect.NextLoopIteration,
				targetKind: OcamlControlTargetKind.Loop,
				targetId: target.id,
				payload: null,
				runtimeTags: [],
				runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
				mechanism: isBreak ? OcamlControlTargetMechanism.RuntimeBreakSignal : OcamlControlTargetMechanism.RuntimeContinueSignal,
				runtimeCapabilityId: isBreak ? OcamlControlPlan.BREAK_SIGNAL_CAPABILITY_ID : OcamlControlPlan.CONTINUE_SIGNAL_CAPABILITY_ID,
				profileEligibility: ["metal", "portable"],
				reason: isBreak ? "This transfer exits its exact lexical loop target." : "This transfer begins the next iteration of its exact lexical loop target.",
				proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
				proofClaim: proofClaim,
				functionId: binding.functionId,
				programRevision: binding.programRevision,
				bodyRevision: binding.bodyRevision,
				pipelineRevision: binding.pipelineRevision
			};
			decisions.push(decision);
			decisionOccurrences.push({
				expression: expression,
				decisionId: decision.id
			});
		}

		function visit(expression:TypedExpr, directRootStatement:Bool, path:String):Void {
			switch (expression.expr) {
				case TReturn(value):
					if (value != null)
						visit(value, false, path + "/return-value");
					if (directRootStatement || !returnFamilyAdmitted)
						return;
					if (value == null && effectOnlyVoidBoundary) {
						final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
						final proofClaim = 'The final typed Haxe body assigns this payloadless return to the current effect-only Void function. The private payloadless runtime signal exits only that exact function boundary and does not invent a Haxe value, carrier, or representation.';
						final decision:OcamlControlDecision = {
							id: controlId(OcamlControlTransferKind.Return, path, binding.functionId),
							source: source,
							kind: OcamlControlTransferKind.Return,
							effect: OcamlControlEffect.ExitFunction,
							targetKind: OcamlControlTargetKind.Function,
							targetId: binding.functionId,
							payload: null,
							runtimeTags: [],
							runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
							mechanism: OcamlControlTargetMechanism.RuntimeVoidReturnSignal,
							runtimeCapabilityId: OcamlControlPlan.VOID_RETURN_SIGNAL_CAPABILITY_ID,
							profileEligibility: ["metal", "portable"],
							reason: "This payloadless return is nested below the function's direct result path, so it exits the current effect-only Void Haxe function through one revision-bound private signal.",
							proofId: OcamlControlPlan.EFFECT_ONLY_VOID_RETURN_PROOF_ID,
							proofClaim: proofClaim,
							functionId: binding.functionId,
							programRevision: binding.programRevision,
							bodyRevision: binding.bodyRevision,
							pipelineRevision: binding.pipelineRevision
						};
						decisions.push(decision);
						decisionOccurrences.push({
							expression: expression,
							decisionId: decision.id
						});
						return;
					}
					final representation = value == null ? null : exactValueRepresentation(value);
					final payload = representation == null ? null : returnPayload(representation, boundaryPayload);
					if (value == null || payload == null) {
						returnFamilyAdmitted = false;
						return;
					}
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final proofId = payload.proofId;
					final proofClaim = payload.proofClaim;
					final decision:OcamlControlDecision = {
						id: controlId(OcamlControlTransferKind.Return, path, binding.functionId),
						source: source,
						kind: OcamlControlTransferKind.Return,
						effect: OcamlControlEffect.ExitFunction,
						targetKind: OcamlControlTargetKind.Function,
						targetId: binding.functionId,
						payload: payload,
						runtimeTags: [],
						runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
						mechanism: OcamlControlTargetMechanism.RuntimeReturnSignal,
						runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID,
						profileEligibility: ["metal", "portable"],
						reason: returnReason(payload),
						proofId: proofId,
						proofClaim: proofClaim,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
					decisions.push(decision);
					decisionOccurrences.push({
						expression: expression,
						decisionId: decision.id
					});
				case TThrow(value):
					visit(value, false, path + "/throw-value");
					final representation = throwRepresentation(value);
					final nominalRepresentation = representation == null ? null : representation.nominalRepresentation;
					final conversion = representation == null ? null : OcamlControlPlan.expectedThrowConversion(representation.semanticTypeId,
						nominalRepresentation != null);
					if (representation == null || conversion == null) {
						throwFamilyAdmitted = false;
						return;
					}
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final proofId = OcamlControlPlan.expectedThrowProofId(representation.semanticTypeId, nominalRepresentation != null);
					if (proofId == null) {
						throwFamilyAdmitted = false;
						return;
					}
					final proofClaim = switch (representation.semanticTypeId) {
						case "Null<Int>":
							"The final typed Haxe body sends one exact Null<Int>/Obj.t value through the compiler-owned Haxe exception channel without another box. The runtime tag comes from the carried value, so non-null matches Int while null remains Dynamic-only.";
						case "Null<Bool>":
							"The final typed Haxe body sends one exact Null<Bool>/Obj.t value through the compiler-owned Haxe exception channel. Null remains the existing sentinel; a non-null carrier is normalized once into the unambiguous boxed-Bool exception representation so it matches Bool rather than Int.";
						case "Dynamic":
							"The final typed Haxe body sends one Dynamic/Obj.t value through the compiler-owned Haxe exception channel without reboxing or changing the payload. Dynamic is the only static tag; the runtime derives any more specific primitive or class tag from the carried value, while null remains Dynamic-only.";
						case "haxe.Exception", "haxe.ValueException":
							'The final typed Haxe body sends one exact ${representation.semanticTypeId}/${representation.carrierTypeId} generated wrapper through the compiler-owned Haxe exception channel. Obj.t is only the in-flight carrier; the original wrapper object is preserved, and its existing runtime class marker derives the applicable haxe.Exception and haxe.ValueException tags without syntax-time hierarchy reconstruction.';
						case _ if (nominalRepresentation != null):
							'The final typed Haxe body sends one already-sealed ${representation.semanticTypeId}/${representation.carrierTypeId} nominal record through the compiler-owned Haxe exception channel. Obj.t is only the in-flight carrier; the existing runtime class marker derives the concrete tag for a non-null record, while null remains Dynamic-only.';
						case _:
							'The final typed Haxe body sends this exact ${representation.semanticTypeId}/${representation.carrierTypeId} value through the compiler-owned Haxe exception channel. The selected payload conversion preserves that represented value in the private Obj.t carrier. The sealed tag policy always admits Dynamic and derives the exact primitive tag from the carried runtime value, so a null String remains Dynamic rather than matching String.';
					};
					final decision:OcamlControlDecision = {
						id: controlId(OcamlControlTransferKind.Throw, path, OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID),
						source: source,
						kind: OcamlControlTransferKind.Throw,
						effect: OcamlControlEffect.RaiseHaxeValue,
						targetKind: OcamlControlTargetKind.HaxeExceptionChannel,
						targetId: OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID,
						payload: {
							inputSemanticTypeId: representation.semanticTypeId,
							inputCarrierTypeId: representation.carrierTypeId,
							inputRepresentationId: representation.representationId,
							signalCarrierTypeId: "Obj.t",
							outputSemanticTypeId: representation.semanticTypeId,
							outputCarrierTypeId: representation.carrierTypeId,
							outputRepresentationId: representation.representationId,
							conversion: conversion,
							nominalRepresentation: nominalRepresentation,
							proofId: proofId,
							proofClaim: proofClaim
						},
						runtimeTags: OcamlControlPlan.expectedThrowTags(representation.semanticTypeId, nominalRepresentation != null),
						runtimeTagPolicy: OcamlControlRuntimeTagPolicy.MergeDynamicWithExactRuntimeValue,
						mechanism: OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal,
						runtimeCapabilityId: OcamlControlPlan.THROW_SIGNAL_CAPABILITY_ID,
						profileEligibility: ["metal", "portable"],
						reason: 'This represented ${representation.semanticTypeId} Haxe value enters the private typed-exception channel and may propagate across calls before a source catch matches its runtime value.',
						proofId: proofId,
						proofClaim: proofClaim,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
					decisions.push(decision);
					decisionOccurrences.push({
						expression: expression,
						decisionId: decision.id
					});
				case TBreak:
					addLoopTransfer(expression, path, OcamlControlTransferKind.Break);
				case TContinue:
					addLoopTransfer(expression, path, OcamlControlTransferKind.Continue);
				case TWhile(condition, loopBody, normalWhile):
					visit(condition, false, path + "/while-condition");
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final kind = normalWhile ? OcamlControlLoopKind.While : OcamlControlLoopKind.DoWhile;
					final target:OcamlControlLoopTarget = {
						id: loopTargetId(kind, path),
						source: source,
						kind: kind,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision,
						proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
						proofClaim: 'The final typed Haxe body owns this lexical $kind target in function "${binding.functionId}".'
					};
					targets.push(target);
					targetOccurrences.push({
						expression: expression,
						targetId: target.id
					});
					loopStack.push(target);
					visit(loopBody, false, path + "/while-body");
					loopStack.pop();
				case TTry(tryExpression, catches):
					var catchTypesAdmitted = catches.length > 0;
					for (entry in catches) {
						if (selectCatchType(entry.v.t) == null) {
							catchTypesAdmitted = false;
							break;
						}
					}
					visit(tryExpression, false, path + "/try-body");
					for (index => entry in catches) {
						final selected = catchTypesAdmitted ? selectCatchType(entry.v.t) : null;
						final nominal = selected == null
							|| selected.nominalRepresentation == null ? null : representations.monomorphicClassValue(selected.semanticTypeId);
						if (nominal != null)
							nominalCatchRepresentations.set(entry.v.id, nominal);
						visit(entry.expr, false, path + "/catch:" + index + "/body");
						if (nominal != null)
							nominalCatchRepresentations.remove(entry.v.id);
					}

					final clauses:Array<OcamlCatchClauseDecision> = [];
					var admitted = catchTypesAdmitted;
					for (index => entry in catches) {
						final selected = selectCatchType(entry.v.t);
						if (selected == null) {
							admitted = false;
							break;
						}
						final clausePath = path + "/catch:" + index;
						final source = OcamlLoweredOrigin.sourceSpan(entry.expr.pos);
						final proofClaim = 'The final typed Haxe try expression assigns source catch clause $index to exact ${selected.semanticTypeId}/${selected.outputCarrierTypeId} binding "${entry.v.name}". The sealed ${selected.matchPolicy} policy selects the first matching source clause, and ${selected.conversion} materializes its variable without reclassifying the payload during OCaml syntax construction.';
						clauses.push({
							id: catchClauseId(clausePath, index, selected.semanticTypeId),
							source: source,
							order: index,
							variableName: entry.v.name,
							semanticTypeId: selected.semanticTypeId,
							signalCarrierTypeId: "Obj.t",
							outputCarrierTypeId: selected.outputCarrierTypeId,
							outputRepresentationId: selected.outputRepresentationId,
							matchPolicy: selected.matchPolicy,
							runtimeTag: selected.runtimeTag,
							conversion: selected.conversion,
							nominalRepresentation: selected.nominalRepresentation,
							bodyResultPolicy: catchBranchResultPolicy(expression.t, entry.expr),
							effects: [
								OcamlCatchEffect.SelectFirstMatchingClause,
								OcamlCatchEffect.BindCatchVariable,
								OcamlCatchEffect.ExecuteCatchBody
							],
							proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
							proofClaim: proofClaim,
							functionId: binding.functionId,
							programRevision: binding.programRevision,
							bodyRevision: binding.bodyRevision,
							pipelineRevision: binding.pipelineRevision
						});
					}
					final trySource = OcamlLoweredOrigin.sourceSpan(expression.pos);
					var admittedChainId:Null<String> = null;
					if (admitted) {
						final chainId = catchChainId(path);
						admittedChainId = chainId;
						final proofClaim = 'The final typed Haxe body fixes all ${clauses.length} catch clauses in source order before target syntax. Compiler-owned Haxe exceptions and target-native exceptions enter the same ordered predicates, but unmatched values return through their original channel and compiler-private return/loop signals bypass every source catch.';
						final chain:OcamlCatchChainDecision = {
							id: chainId,
							source: trySource,
							clauses: clauses,
							tryBodyResultPolicy: catchBranchResultPolicy(expression.t, tryExpression),
							inputChannels: [
								OcamlCatchInputChannel.HaxeExceptionSignal,
								OcamlCatchInputChannel.TargetNativeException
							],
							targetNativeRuntimeTags: ["OcamlExn"],
							haxeUnmatchedPolicy: OcamlCatchUnmatchedPolicy.RethrowHaxeExceptionSignal,
							targetNativeUnmatchedPolicy: OcamlCatchUnmatchedPolicy.ReraiseTargetNativeException,
							privateControlPolicy: OcamlCatchPrivateControlPolicy.PropagatePrivateControlSignals,
							runtimeCapabilityId: OcamlControlPlan.CATCH_SIGNAL_CAPABILITY_ID,
							profileEligibility: ["metal", "portable"],
							reason: "This complete source catch chain has represented primitive, monomorphic-class, Haxe exception-wrapper, or Dynamic matching and payload binding fixed before OCaml syntax.",
							proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
							proofClaim: proofClaim,
							functionId: binding.functionId,
							programRevision: binding.programRevision,
							bodyRevision: binding.bodyRevision,
							pipelineRevision: binding.pipelineRevision
						};
						catchChains.push(chain);
					}
					catchOccurrences.push({
						expression: expression,
						occurrenceId: catchOccurrenceId(path),
						source: trySource,
						chainId: admittedChainId
					});
				case TFunction(_):
					// The nested function owns independent function and loop targets.
				case TBlock(expressions):
					for (index => child in expressions)
						visit(child, false, path + "/block:" + index);
				case _:
					var childIndex = 0;
					TypedExprTools.iter(expression, child -> {
						final childPath = path + "/child:" + childIndex;
						childIndex++;
						visit(child, false, childPath);
					});
			}
		}

		switch (body.expr) {
			case TBlock(expressions):
				for (index => expression in expressions)
					visit(expression, true, "root/block:" + index);
			case _:
				visit(body, true, "root");
		}

		if (!returnFamilyAdmitted) {
			decisions = decisions.filter(decision -> decision.kind != OcamlControlTransferKind.Return);
			final admittedIds = [for (decision in decisions) decision.id => true];
			decisionOccurrences = decisionOccurrences.filter(occurrence -> admittedIds.exists(occurrence.decisionId));
		}
		if (!loopFamilyAdmitted) {
			decisions = decisions.filter(decision -> decision.targetKind != OcamlControlTargetKind.Loop);
			final admittedIds = [for (decision in decisions) decision.id => true];
			decisionOccurrences = decisionOccurrences.filter(occurrence -> admittedIds.exists(occurrence.decisionId));
			targets.resize(0);
			targetOccurrences.resize(0);
		}
		if (!throwFamilyAdmitted) {
			decisions = decisions.filter(decision -> decision.kind != OcamlControlTransferKind.Throw);
			final admittedIds = [for (decision in decisions) decision.id => true];
			decisionOccurrences = decisionOccurrences.filter(occurrence -> admittedIds.exists(occurrence.decisionId));
		}
		return new OcamlControlPlan(returnFamilyAdmitted, loopFamilyAdmitted, throwFamilyAdmitted, binding, targets, decisions, targetOccurrences,
			decisionOccurrences, catchChains, catchOccurrences);
	}

	static function catchBranchResultPolicy(tryResultType:Type, branch:TypedExpr):OcamlCatchBranchResultPolicy {
		return isVoid(tryResultType)
			&& !definitelyTransfers(branch) ? OcamlCatchBranchResultPolicy.DiscardCompletedValueToUnit : OcamlCatchBranchResultPolicy.PreserveTypedResult;
	}

	static function isVoid(type:Type):Bool {
		return switch (haxe.macro.TypeTools.follow(type)) {
			case TAbstract(abstractRef, _):
				final abstractType = abstractRef.get();
				(abstractType.pack ?? []).length == 0 && abstractType.name == "Void";
			case _:
				false;
		}
	}

	/**
		Reports whether the generated branch remains target-polymorphic.

		A block is decided by its final target-visible expression. An earlier
		throw makes later Haxe source unreachable at runtime, but the OCaml
		type-checker still assigns the sequence the type of its emitted suffix.
		Unknown shapes return false so a completing `Void` branch becomes `unit`.
	**/
	static function definitelyTransfers(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TReturn(_) | TThrow(_):
				true;
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
				definitelyTransfers(inner);
			case TBlock(expressions): expressions.length > 0 && definitelyTransfers(expressions[expressions.length - 1]);
			case TIf(_, thenExpression, elseExpression): elseExpression != null && definitelyTransfers(thenExpression) && definitelyTransfers(elseExpression);
			case TSwitch(_, cases, defaultExpression):
				defaultExpression != null
				&& cases.length > 0
				&& Lambda.foreach(cases, entry -> definitelyTransfers(entry.expr))
				&& definitelyTransfers(defaultExpression);
			case TTry(tryExpression, catches): definitelyTransfers(tryExpression) && catches.length > 0 && Lambda.foreach(catches,
					entry -> definitelyTransfers(entry.expr));
			case _:
				false;
		}
	}

	function selectCatchType(type:Type):Null<{
		semanticTypeId:String,
		outputCarrierTypeId:String,
		outputRepresentationId:String,
		matchPolicy:OcamlCatchMatchPolicy,
		runtimeTag:Null<String>,
		conversion:OcamlCatchPayloadConversion,
		nominalRepresentation:Null<OcamlControlNominalRepresentationProof>
	}> {
		if (OcamlRepresentationRegistry.isExactInt(type)) {
			final representation = representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			return {
				semanticTypeId: "Int",
				outputCarrierTypeId: representation.carrierTypeId,
				outputRepresentationId: representation.id,
				matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
				runtimeTag: "Int",
				conversion: OcamlCatchPayloadConversion.RecoverExactValue,
				nominalRepresentation: null
			};
		}
		if (OcamlRepresentationRegistry.isExactBool(type)) {
			final representation = representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
			return {
				semanticTypeId: "Bool",
				outputCarrierTypeId: representation.carrierTypeId,
				outputRepresentationId: representation.id,
				matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
				runtimeTag: "Bool",
				conversion: OcamlCatchPayloadConversion.RecoverCheckedBool,
				nominalRepresentation: null
			};
		}
		if (OcamlRepresentationRegistry.isExactString(type)) {
			final representation = representations.selectExactString(OcamlRepresentationDomain.InternalValue);
			return {
				semanticTypeId: "String",
				outputCarrierTypeId: representation.carrierTypeId,
				outputRepresentationId: representation.id,
				matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
				runtimeTag: "String",
				conversion: OcamlCatchPayloadConversion.RecoverExactValue,
				nominalRepresentation: null
			};
		}
		final haxeExceptionTypeId = OcamlControlPlan.haxeExceptionWrapperTypeId(type);
		if (haxeExceptionTypeId != null) {
			return haxeExceptionTypeId == "haxe.Exception" ? {
				semanticTypeId: haxeExceptionTypeId,
				outputCarrierTypeId: "Haxe_Exception.t",
				outputRepresentationId: OcamlControlPlan.HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID,
				matchPolicy: OcamlCatchMatchPolicy.MatchHaxeException,
				runtimeTag: null,
				conversion: OcamlCatchPayloadConversion.PreserveOrWrapHaxeException,
				nominalRepresentation: null
			} : {
				semanticTypeId: haxeExceptionTypeId,
				outputCarrierTypeId: "Haxe_ValueException.t",
				outputRepresentationId: OcamlControlPlan.HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID,
				matchPolicy: OcamlCatchMatchPolicy.MatchHaxeValueException,
				runtimeTag: null,
				conversion: OcamlCatchPayloadConversion.PreserveOrWrapHaxeValueException,
				nominalRepresentation: null
				};
		}
		final nominalClass = representations.monomorphicClassForType(type);
		if (nominalClass != null) {
			final representation = representations.monomorphicClassValue(nominalClass.semanticTypeId);
			final nominalRepresentation = representation == null ? null : nominalProofFor(representation);
			if (representation == null || nominalRepresentation == null)
				return null;
			return {
				semanticTypeId: representation.semanticTypeId,
				outputCarrierTypeId: representation.carrierTypeId,
				outputRepresentationId: representation.id,
				matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
				runtimeTag: representation.semanticTypeId,
				conversion: OcamlCatchPayloadConversion.RecoverNominalValue,
				nominalRepresentation: nominalRepresentation
			};
		}
		return switch (haxe.macro.TypeTools.follow(type)) {
			case TDynamic(_):
				{
					semanticTypeId: "Dynamic",
					outputCarrierTypeId: "Obj.t",
					outputRepresentationId: OcamlControlPlan.DYNAMIC_CONTROL_REPRESENTATION_ID,
					matchPolicy: OcamlCatchMatchPolicy.MatchAll,
					runtimeTag: null,
					conversion: OcamlCatchPayloadConversion.PreserveDynamicCarrier,
					nominalRepresentation: null
				};
			case _:
				null;
		}
	}

	function exactValueRepresentation(expression:TypedExpr):Null<OcamlRepresentationDecision> {
		if (OcamlRepresentationRegistry.isExactInt(expression.t))
			return representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactBool(expression.t))
			return representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactNullInt(expression.t))
			return representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactNullBool(expression.t))
			return representations.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactString(expression.t))
			return representations.selectExactString(OcamlRepresentationDomain.InternalValue);
		final unwrapped = unwrapTransparent(expression);
		switch (unwrapped.expr) {
			case TLocal(local):
				final nominalCatchRepresentation = nominalCatchRepresentations.get(local.id);
				if (nominalCatchRepresentation != null
					&& nominalCatchRepresentation.semanticTypeId == OcamlRepresentationRegistry.monomorphicClassSemanticTypeId(unwrapped.t)) {
					return nominalCatchRepresentation;
				}
				final reference = localRepresentations.referenceFor(local.id);
				if (reference == null
					|| reference.domain != OcamlRepresentationDomain.InternalValue
					|| reference.semanticTypeId != OcamlRepresentationRegistry.monomorphicClassSemanticTypeId(unwrapped.t)) {
					return null;
				}
				final representation = representations.monomorphicClassValue(reference.semanticTypeId);
				return representation != null && representation.id == reference.representationId ? representation : null;
			case TCast(child, _) if (representations.monomorphicClassForType(child.t) != null):
				return exactValueRepresentation(child);
			case _:
		}
		return null;
	}

	/**
		Selects a represented value that can cross the exception channel opaquely.

		Throwing does not read fields or expose a callable/storage carrier, so an
		exact whole-program-monomorphic class can use its nullable nominal record
		decision even when the surrounding expression has no separately admitted
		local or call-boundary proof. `Obj.repr` preserves either the real record
		or the null sentinel, and runtime marker inspection adds the class tag only
		for a real record. A value statically typed as `Dynamic` already uses the
		private `Obj.t` carrier; selecting it here preserves that carrier only for
		exception transport and does not register a general Dynamic representation.
		Other control families remain on their narrower proofs.
	**/
	function throwRepresentation(expression:TypedExpr):Null<OcamlControlThrowRepresentation> {
		final haxeExceptionTypeId = OcamlControlPlan.haxeExceptionWrapperTypeId(expression.t);
		if (haxeExceptionTypeId != null) {
			return haxeExceptionTypeId == "haxe.Exception" ? {
				semanticTypeId: haxeExceptionTypeId,
				carrierTypeId: "Haxe_Exception.t",
				representationId: OcamlControlPlan.HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID,
				nominalRepresentation: null
			} : {
				semanticTypeId: haxeExceptionTypeId,
				carrierTypeId: "Haxe_ValueException.t",
				representationId: OcamlControlPlan.HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID,
				nominalRepresentation: null
				};
		}
		final exact = exactValueRepresentation(expression);
		if (exact != null) {
			return {
				semanticTypeId: exact.semanticTypeId,
				carrierTypeId: exact.carrierTypeId,
				representationId: exact.id,
				nominalRepresentation: nominalProofFor(exact)
			};
		}
		switch (haxe.macro.TypeTools.follow(expression.t)) {
			case TDynamic(_):
				return {
					semanticTypeId: "Dynamic",
					carrierTypeId: "Obj.t",
					representationId: OcamlControlPlan.DYNAMIC_CONTROL_REPRESENTATION_ID,
					nominalRepresentation: null
				};
			case _:
		}
		final nominalClass = representations.monomorphicClassForType(expression.t);
		if (nominalClass == null)
			return null;
		final representation = representations.monomorphicClassValue(nominalClass.semanticTypeId);
		return representation == null ? null : {
			semanticTypeId: representation.semanticTypeId,
			carrierTypeId: representation.carrierTypeId,
			representationId: representation.id,
			nominalRepresentation: nominalProofFor(representation)
		};
	}

	static function returnPayload(input:OcamlRepresentationDecision, output:OcamlCallValuePlan):Null<OcamlControlPayloadPlan> {
		final sameSide = input.semanticTypeId == output.outputSemanticTypeId
			&& input.carrierTypeId == output.outputCarrierTypeId
			&& input.id == output.outputRepresentationId;
		if (sameSide && OcamlControlPlan.isAdmittedExactSide(input.semanticTypeId, input.carrierTypeId, input.id)) {
			final proofClaim = 'The final typed Haxe body assigns this return to the current ${input.semanticTypeId} function. The selected private runtime signal boxes the exact ${input.carrierTypeId} carrier only while control is in flight, and the matching function boundary recovers that same sealed carrier before it can cross the callable ABI.';
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.BoxAndRecoverExactValue, OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID,
				proofClaim);
		}
		if (sameSide && input.boxingPolicy == OcamlRepresentationBoxingPolicy.NullableNominalRecordCarrier) {
			final nominalRepresentation = nominalProofFor(input);
			if (nominalRepresentation == null)
				return null;
			final proofClaim = 'The final typed Haxe body returns one already-sealed ${input.semanticTypeId} nominal record. The private runtime signal uses Obj.t only while control is in flight, then the matching function boundary recovers ${input.carrierTypeId} under exact layout ${nominalRepresentation.layoutRevision}. Reference identity, shared field mutation, and the callable result carrier remain unchanged.';
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.BoxAndRecoverNominalValue, OcamlControlPlan.EXACT_NOMINAL_RETURN_PROOF_ID,
				proofClaim, nominalRepresentation);
		}
		if (sameSide && OcamlControlPlan.isAdmittedNullableSide(input.semanticTypeId, input.carrierTypeId, input.id)) {
			final proofClaim = 'The final typed Haxe body assigns this return to the current ${input.semanticTypeId} function. The selected private runtime signal already carries the exact ${input.carrierTypeId} nullable value, so syntax must preserve that carrier without another box, unchecked cast, or boundary recovery.';
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.PreserveNullableCarrier, OcamlControlPlan.NULLABLE_CARRIER_RETURN_PROOF_ID,
				proofClaim);
		}
		if (input.semanticTypeId == "Int" && output.outputSemanticTypeId == "Null<Int>") {
			final proofClaim = "The final typed Haxe body converts this exact Int return to the function's exact Null<Int> Obj.t carrier once before the private return signal. The owning function boundary preserves that resulting carrier unchanged.";
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.BoxExactIntToNullableCarrier,
				OcamlControlPlan.NULLABLE_INT_CONVERSION_RETURN_PROOF_ID, proofClaim);
		}
		if (input.semanticTypeId == "Bool" && output.outputSemanticTypeId == "Null<Bool>") {
			final proofClaim = "The final typed Haxe body converts this exact Bool return to the function's exact Null<Bool> Obj.t carrier once before the private return signal. The owning function boundary preserves that resulting carrier unchanged.";
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.BoxExactBoolToNullableCarrier,
				OcamlControlPlan.NULLABLE_BOOL_CONVERSION_RETURN_PROOF_ID, proofClaim);
		}
		return null;
	}

	static function nominalProofFor(representation:OcamlRepresentationDecision):Null<OcamlControlNominalRepresentationProof> {
		final targetModuleName = representation.nominalTargetModuleName;
		final targetTypeName = representation.nominalTargetTypeName;
		final layoutRevision = representation.nominalLayoutRevision;
		if (representation.boxingPolicy != OcamlRepresentationBoxingPolicy.NullableNominalRecordCarrier
			|| targetModuleName == null
			|| targetTypeName == null
			|| layoutRevision == null) {
			return null;
		}
		return {
			targetModuleName: targetModuleName,
			targetTypeName: targetTypeName,
			layoutRevision: layoutRevision,
			representationProofId: representation.proof.id
		};
	}

	static function makeReturnPayload(input:OcamlRepresentationDecision, output:OcamlCallValuePlan, conversion:OcamlControlPayloadConversion, proofId:String,
			proofClaim:String, ?nominalRepresentation:OcamlControlNominalRepresentationProof):OcamlControlPayloadPlan {
		return {
			inputSemanticTypeId: input.semanticTypeId,
			inputCarrierTypeId: input.carrierTypeId,
			inputRepresentationId: input.id,
			signalCarrierTypeId: "Obj.t",
			outputSemanticTypeId: output.outputSemanticTypeId,
			outputCarrierTypeId: output.outputCarrierTypeId,
			outputRepresentationId: output.outputRepresentationId,
			conversion: conversion,
			nominalRepresentation: nominalRepresentation,
			proofId: proofId,
			proofClaim: proofClaim
		};
	}

	static function returnReason(payload:OcamlControlPayloadPlan):String {
		return switch (payload.conversion) {
			case PreserveNullableCarrier:
				'This return is nested below the function\'s direct result path, so it preserves the current exact-${payload.outputSemanticTypeId} carrier through one revision-bound private runtime signal.';
			case BoxExactIntToNullableCarrier, BoxExactBoolToNullableCarrier:
				'This return is nested below the function\'s direct result path, so it performs the sealed ${payload.inputSemanticTypeId}-to-${payload.outputSemanticTypeId} conversion before one revision-bound private runtime signal.';
			case BoxAndRecoverNominalValue:
				'This return is nested below the function\'s direct result path, so it preserves the sealed ${payload.outputSemanticTypeId} nominal record through one revision-bound private runtime signal.';
			case _:
				'This return is nested below the function\'s direct result path, so it exits the current exact-${payload.outputSemanticTypeId} Haxe function through one revision-bound private runtime signal.';
		};
	}

	function loopTargetId(kind:OcamlControlLoopKind, path:String):String {
		return "control-target:loop:" + Sha256.encode(binding.functionId + "|" + (kind : String) + "|" + path).substr(0, 24);
	}

	function controlId(kind:OcamlControlTransferKind, path:String, targetId:String):String {
		return "control:"
			+ (kind : String)
			+ ":"
			+ Sha256.encode(binding.functionId + "|" + (kind : String) + "|" + targetId + "|" + path).substr(0, 24);
	}

	function catchChainId(path:String):String {
		return "control-catch-chain:" + Sha256.encode(binding.functionId + "|" + path).substr(0, 24);
	}

	function catchOccurrenceId(path:String):String {
		return "control-catch-occurrence:" + Sha256.encode(binding.functionId + "|" + path).substr(0, 24);
	}

	function catchClauseId(path:String, order:Int, semanticTypeId:String):String {
		return "control-catch-clause:" + Sha256.encode(binding.functionId + "|" + path + "|" + order + "|" + semanticTypeId).substr(0, 24);
	}

	static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	function admittedBoundaryPayload(boundary:Null<OcamlCallableBoundaryPlan>):Null<OcamlCallValuePlan> {
		if (boundary == null
			|| boundary.kind != OcamlCallKind.DirectStaticHaxeMethod
			|| boundary.resultKind != OcamlCallResultKind.Value
			|| boundary.result == null) {
			return null;
		}
		final result = boundary.result;
		final exactIdentity = result.inputSemanticTypeId == result.outputSemanticTypeId
			&& result.inputCarrierTypeId == result.outputCarrierTypeId
			&& result.inputRepresentationId == result.outputRepresentationId
			&& result.conversion == OcamlCallCarrierConversion.Identity
			&& OcamlControlPlan.isAdmittedExactSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId);
		if (exactIdentity)
			return OcamlCallPlan.copyValue(result);
		final nominalRepresentation = representations.monomorphicClassValue(result.outputSemanticTypeId);
		final nominalIdentity = nominalRepresentation != null
			&& result.inputSemanticTypeId == nominalRepresentation.semanticTypeId
			&& result.inputCarrierTypeId == nominalRepresentation.carrierTypeId
			&& result.inputRepresentationId == nominalRepresentation.id
			&& result.outputSemanticTypeId == nominalRepresentation.semanticTypeId
			&& result.outputCarrierTypeId == nominalRepresentation.carrierTypeId
			&& result.outputRepresentationId == nominalRepresentation.id
			&& result.conversion == OcamlCallCarrierConversion.Identity;
		if (nominalIdentity)
			return OcamlCallPlan.copyValue(result);
		final nullableOutput = OcamlControlPlan.isAdmittedNullableSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId);
		final validDirectConversion = (result.inputSemanticTypeId == "Int"
			&& result.outputSemanticTypeId == "Null<Int>"
			&& result.conversion == OcamlCallCarrierConversion.BoxExactIntToNullableInt)
			|| (result.inputSemanticTypeId == "Bool"
				&& result.outputSemanticTypeId == "Null<Bool>"
				&& result.conversion == OcamlCallCarrierConversion.BoxExactBoolToNullableBool)
			|| (result.inputSemanticTypeId == result.outputSemanticTypeId
				&& result.inputCarrierTypeId == result.outputCarrierTypeId
				&& result.inputRepresentationId == result.outputRepresentationId
				&& result.conversion == OcamlCallCarrierConversion.Identity);
		if (!nullableOutput || !validDirectConversion)
			return null;
		return {
			index: -1,
			parameterOptional: false,
			inputSemanticTypeId: result.outputSemanticTypeId,
			inputCarrierTypeId: result.outputCarrierTypeId,
			inputRepresentationId: result.outputRepresentationId,
			outputSemanticTypeId: result.outputSemanticTypeId,
			outputCarrierTypeId: result.outputCarrierTypeId,
			outputRepresentationId: result.outputRepresentationId,
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: result.proofId,
			proofClaim: result.proofClaim
		};
	}

	static function unwrapTransparent(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, child), TParenthesis(child): unwrapTransparent(child);
			case _: expression;
		}
	}

	static function admittedEffectOnlyVoidBoundary(boundary:Null<OcamlCallableBoundaryPlan>):Bool {
		return boundary != null
			&& boundary.kind == OcamlCallKind.DirectStaticHaxeMethod
			&& boundary.resultKind == OcamlCallResultKind.EffectOnlyVoid
			&& boundary.result == null;
	}
}
#end
