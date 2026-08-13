package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionBlocker;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionContract;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionFamily;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionSnapshot;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionStatus;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlCatchAdmission;
import reflaxe.ocaml.lowered.OcamlEnumDynamicCarrier.OcamlEnumDynamicCarrierIdentity;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary.OcamlFunctionResultBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlTypedFunctionResultBoundary.OcamlTypedFunctionResultBoundaryPlan;
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
	final BoxAndRecoverTypedFunctionResult = "box-and-recover-typed-function-result";
	final BoxBoolAndRecoverDynamicTypedFunctionResult = "box-bool-and-recover-dynamic-typed-function-result";
	final PreserveNullableCarrier = "preserve-nullable-carrier";
	final PreserveAnonymousCarrier = "preserve-anonymous-carrier";
	final PreserveDynamicReturnCarrier = "preserve-dynamic-return-carrier";
	final BoxExactIntToNullableCarrier = "box-exact-int-to-nullable-carrier";
	final BoxExactBoolToNullableCarrier = "box-exact-bool-to-nullable-carrier";
	final BoxExactEnumToNullableCarrier = "box-exact-enum-to-nullable-carrier";
	final ReprAndRecoverExactValue = "repr-and-recover-exact-value";
	final BoxBoolAndRecoverExactValue = "box-bool-and-recover-exact-value";
	final PreserveNullableIntThrowCarrier = "preserve-nullable-int-throw-carrier";
	final NormalizeNullableBoolThrowCarrier = "normalize-nullable-bool-throw-carrier";
	final BoxRepresentedArrayThrowCarrier = "box-represented-array-throw-carrier";
	final BoxNominalThrowCarrier = "box-nominal-throw-carrier";
	final PreserveDynamicThrowCarrier = "preserve-dynamic-throw-carrier";
	final BoxHaxeExceptionWrapperThrowCarrier = "box-haxe-exception-wrapper-throw-carrier";
	final BoxEnumThrowCarrier = "box-enum-throw-carrier";
	final BoxRuntimeClassThrowCarrier = "box-runtime-class-throw-carrier";
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
	final RecoverEnumValue = "recover-enum-value";
	final RecoverRuntimeClassValue = "recover-runtime-class-value";
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
	How a Haxe expression behaves when OCaml syntax needs a statement result.

	Most statement expressions can finish normally, so their value must be
	discarded to OCaml `unit`. An expression whose every visible branch returns or
	throws cannot finish normally. Keeping that expression polymorphic prevents an
	outer `ignore` from changing the result type recovered by the function's
	private return handler.
**/
enum abstract OcamlStatementResultPolicy(String) from String to String {
	final PreserveNonLocalResult = "preserve-non-local-result";
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

	/** Exact registry revision consumed by a program-owned represented value. */
	final ?representationRevision:String;

	/** Program-owned array descriptor consumed by a represented-array crossing. */
	final ?arrayDescriptorId:String;

	/** Exact content revision of `arrayDescriptorId`. */
	final ?arrayDescriptorRevision:String;

	/** Exact direct-array literal occurrence consumed by this throw, when any. */
	final ?arrayLiteralProducerId:String;

	/** Revision of the function's complete literal-construction plan. */
	final ?arrayLiteralProducerPlanRevision:String;

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
	final representationRevision:Null<String>;
	final arrayDescriptorId:Null<String>;
	final arrayDescriptorRevision:Null<String>;
	final arrayLiteralProducerId:Null<String>;
	final arrayLiteralProducerPlanRevision:Null<String>;
	final nominalRepresentation:Null<OcamlControlNominalRepresentationProof>;
	final enumIdentity:Null<OcamlEnumDynamicCarrierIdentity>;
	final runtimeClassIdentity:Null<OcamlRuntimeClassCarrierIdentity>;
}

/**
	The plain-data identity for a generated class that crosses an exception.

	Generated class records contain a `__hx_type` marker. The runtime uses that
	marker to find the concrete class and its parent classes. This identity does
	not define a second class layout. It only lets the control plan box the value,
	check a class tag, and recover the typed catch variable after that check.
**/
typedef OcamlRuntimeClassCarrierIdentity = {
	final semanticTypeId:String;
	final carrierTypeId:String;
	final throwRepresentationId:String;
	final catchRepresentationId:String;
}

/** One represented array selection and its optional direct-literal owner. */
private typedef OcamlRepresentedArrayThrowSelection = {
	final representation:OcamlRepresentationDecision;
	final arrayLiteralProducerId:Null<String>;
	final arrayLiteralProducerPlanRevision:Null<String>;
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

/**
	One exact typed branch whose statement-result behavior was fixed by planning.

	The expression reference is request-local lookup only. The stable identity,
	source span, and policy participate in the detached plan revision.
**/
typedef OcamlStatementResultOccurrence = {
	final expression:TypedExpr;
	final occurrenceId:String;
	final source:OcamlLoweredSourceSpan;
	final policy:OcamlStatementResultPolicy;
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

	`chainId = null` records that planning found no admitted chain. This remains
	useful for reporting an empty or blocked occurrence, but it is not permission
	for syntax to rebuild a non-empty catch: the function sealer rejects that case.
	The stable occurrence identity and source participate in the plan revision, so
	removing an admitted chain cannot silently look like an unobserved expression.
**/
typedef OcamlCatchChainOccurrence = {
	final expression:TypedExpr;
	final occurrenceId:String;
	final source:OcamlLoweredSourceSpan;
	final chainId:Null<String>;
	final tryBodyResultPolicy:OcamlCatchBranchResultPolicy;
	final clauseBodyResultPolicies:Array<OcamlCatchBranchResultPolicy>;
}

/**
	How every completed branch of one exact typed `try` reaches its result type.

	The admitted catch chain carries the same policies; this detached view lets
	validation compare the exact typed `try` occurrence with that chain. OCaml
	syntax cannot infer a policy from target expressions or change which catch
	clause receives an exception.
**/
typedef OcamlCatchBranchResultDisposition = {
	final occurrenceId:String;
	final tryBodyResultPolicy:OcamlCatchBranchResultPolicy;
	final clauseBodyResultPolicies:Array<OcamlCatchBranchResultPolicy>;
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
	public static inline final TYPED_FUNCTION_RESULT_RETURN_PROOF_ID = OcamlTypedFunctionResultBoundary.PROOF_ID;
	public static inline final DYNAMIC_RETURN_PROOF_ID = "dynamic-carrier-return-control-v1";
	public static inline final EXACT_NOMINAL_RETURN_PROOF_ID = "exact-monomorphic-class-early-return-control-v1";
	public static inline final NULLABLE_CARRIER_RETURN_PROOF_ID = "exact-nullable-carrier-early-return-control-v1";
	public static inline final ANONYMOUS_CARRIER_RETURN_PROOF_ID = "exact-anonymous-carrier-early-return-control-v1";
	public static inline final NULLABLE_INT_CONVERSION_RETURN_PROOF_ID = "exact-int-to-nullable-early-return-control-v1";
	public static inline final NULLABLE_BOOL_CONVERSION_RETURN_PROOF_ID = "exact-bool-to-nullable-early-return-control-v1";
	public static inline final NULLABLE_ENUM_CONVERSION_RETURN_PROOF_ID = "exact-enum-to-nullable-early-return-control-v1";
	public static inline final EFFECT_ONLY_VOID_RETURN_PROOF_ID = "effect-only-void-early-return-control-v1";
	public static inline final LEXICAL_LOOP_CONTROL_PROOF_ID = "lexical-loop-control-v1";
	public static inline final EXACT_VALUE_THROW_PROOF_ID = "exact-value-throw-control-v1";
	public static inline final NULLABLE_INT_THROW_PROOF_ID = "nullable-int-throw-control-v1";
	public static inline final NULLABLE_BOOL_THROW_PROOF_ID = "nullable-bool-throw-control-v1";
	public static inline final REPRESENTED_ARRAY_THROW_PROOF_ID = "represented-array-throw-control-v1";
	public static inline final EXACT_NOMINAL_THROW_PROOF_ID = "exact-monomorphic-class-throw-control-v1";
	public static inline final DYNAMIC_THROW_PROOF_ID = "dynamic-carrier-throw-control-v1";
	public static inline final HAXE_EXCEPTION_WRAPPER_THROW_PROOF_ID = "exact-haxe-exception-wrapper-throw-control-v1";
	public static inline final EXACT_ENUM_THROW_PROOF_ID = "exact-enum-constructor-throw-control-v1";
	public static inline final RUNTIME_CLASS_THROW_PROOF_ID = "runtime-tagged-class-throw-control-v1";
	public static inline final REPRESENTED_VALUE_CATCH_PROOF_ID = "represented-value-catch-control-v6";
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
	public static inline final ENUM_THROW_CONTROL_REPRESENTATION_PREFIX = "control-representation:enum-direct-v1:";
	public static inline final ENUM_CATCH_CONTROL_REPRESENTATION_PREFIX = "control-representation:enum-catch-v1:";
	public static inline final RUNTIME_CLASS_CARRIER_PREFIX = "haxe-class-runtime-tagged-carrier-v1:";
	public static inline final RUNTIME_CLASS_THROW_CONTROL_REPRESENTATION_PREFIX = "control-representation:runtime-class-throw-v1:";
	public static inline final RUNTIME_CLASS_CATCH_CONTROL_REPRESENTATION_PREFIX = "control-representation:runtime-class-catch-v1:";

	public final returnFamilyAdmitted:Bool;
	public final loopFamilyAdmitted:Bool;
	public final throwFamilyAdmitted:Bool;
	public final binding:OcamlFunctionPlanBinding;
	public final admission:Null<OcamlControlAdmissionSnapshot>;
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
	final catchBranchResultsByExpression:ObjectMap<TypedExpr, OcamlCatchBranchResultDisposition> = new ObjectMap();
	final statementResultPolicyByExpression:ObjectMap<TypedExpr, OcamlStatementResultPolicy> = new ObjectMap();
	final hasOccurrenceIndex:Bool;
	final hasCatchOccurrenceIndex:Bool;
	final hasStatementResultIndex:Bool;
	final catchOccurrenceFingerprints:Array<String>;
	final statementResultFingerprints:Array<String>;

	public function new(returnFamilyAdmitted:Bool, loopFamilyAdmitted:Bool, throwFamilyAdmitted:Bool, binding:OcamlFunctionPlanBinding,
			targets:Array<OcamlControlLoopTarget>, decisions:Array<OcamlControlDecision>, ?targetOccurrences:Array<OcamlControlLoopTargetOccurrence>,
			?decisionOccurrences:Array<OcamlControlDecisionOccurrence>, ?catchChains:Array<OcamlCatchChainDecision>,
			?catchOccurrences:Array<OcamlCatchChainOccurrence>, ?admission:OcamlControlAdmissionSnapshot,
			?statementResultOccurrences:Array<OcamlStatementResultOccurrence>) {
		this.returnFamilyAdmitted = returnFamilyAdmitted;
		this.loopFamilyAdmitted = loopFamilyAdmitted;
		this.throwFamilyAdmitted = throwFamilyAdmitted;
		this.binding = copyBinding(binding);
		if ((targetOccurrences == null) != (decisionOccurrences == null))
			throw 'reflaxe.ocaml [ocaml-control:incomplete-occurrence-index]: loop-target and transfer occurrence indexes must be supplied together';
		hasOccurrenceIndex = targetOccurrences != null;
		hasCatchOccurrenceIndex = catchOccurrences != null;
		hasStatementResultIndex = statementResultOccurrences != null;

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
			final decision = decisionsById.get(occurrence.decisionId);
			if (decision == null)
				throw 'reflaxe.ocaml [ocaml-control:missing-decision-occurrence]: typed control occurrence refers to missing decision "${occurrence.decisionId}"';
			final occurrenceSource = OcamlLoweredOrigin.sourceSpan(occurrence.expression.pos);
			if (sourceKey(decision.source) != sourceKey(occurrenceSource)) {
				throw 'reflaxe.ocaml [ocaml-control:stale-decision-source]: control decision "${decision.id}" belongs to ${sourceKey(decision.source)}, but its exact typed occurrence is at ${sourceKey(occurrenceSource)}';
			}
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
			final catchCount = switch (occurrence.expression.expr) {
				case TTry(_, catches): catches.length;
				case _: -1;
			};
			if (occurrence.occurrenceId.length == 0
				|| occurrence.source.file.length == 0
				|| occurrence.source.min < 0
				|| occurrence.source.max < occurrence.source.min
				|| catchCount < 0
				|| !isCatchBranchResultPolicy(occurrence.tryBodyResultPolicy)
				|| occurrence.clauseBodyResultPolicies.length != catchCount
				|| Lambda.exists(occurrence.clauseBodyResultPolicies, policy -> !isCatchBranchResultPolicy(policy))) {
				throw 'reflaxe.ocaml [ocaml-control:invalid-catch-occurrence]: typed try occurrence has incomplete identity, source, or branch-result policies';
			}
			if (indexedCatchOccurrenceIds.exists(occurrence.occurrenceId))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-catch-occurrence]: catch occurrence "${occurrence.occurrenceId}" appears more than once';
			if (catchDispositionByExpression.exists(occurrence.expression))
				throw 'reflaxe.ocaml [ocaml-control:ambiguous-catch-occurrence]: one typed try node has more than one planned disposition';
			if (occurrence.chainId != null) {
				final chain = catchChainsById.get(occurrence.chainId);
				if (chain == null)
					throw 'reflaxe.ocaml [ocaml-control:missing-catch-occurrence]: typed try occurrence refers to missing catch chain "${occurrence.chainId}"';
				if (chain.tryBodyResultPolicy != occurrence.tryBodyResultPolicy
					|| chain.clauses.length != occurrence.clauseBodyResultPolicies.length
					|| Lambda.exists(chain.clauses, clause -> clause.bodyResultPolicy != occurrence.clauseBodyResultPolicies[clause.order])) {
					throw 'reflaxe.ocaml [ocaml-control:stale-catch-result-policy]: admitted catch chain "${occurrence.chainId}" disagrees with its typed occurrence result policies';
				}
				if (indexedCatchChainIds.exists(occurrence.chainId))
					throw 'reflaxe.ocaml [ocaml-control:duplicate-catch-occurrence]: catch chain "${occurrence.chainId}" is indexed by more than one typed occurrence';
				catchChainIdByExpression.set(occurrence.expression, occurrence.chainId);
				indexedCatchChainIds.set(occurrence.chainId, true);
			}
			catchDispositionByExpression.set(occurrence.expression, true);
			catchBranchResultsByExpression.set(occurrence.expression, {
				occurrenceId: occurrence.occurrenceId,
				tryBodyResultPolicy: occurrence.tryBodyResultPolicy,
				clauseBodyResultPolicies: occurrence.clauseBodyResultPolicies.copy()
			});
			indexedCatchOccurrenceIds.set(occurrence.occurrenceId, true);
			normalizedCatchOccurrenceFingerprints.push([
				occurrence.occurrenceId,
				sourceKey(occurrence.source),
				occurrence.chainId ?? "unadmitted-catch-chain",
				(occurrence.tryBodyResultPolicy : String),
				occurrence.clauseBodyResultPolicies.map(policy -> (policy : String)).join(",")
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
		final indexedStatementResultIds:Map<String, Bool> = [];
		final normalizedStatementResultFingerprints:Array<String> = [];
		for (occurrence in statementResultOccurrences ?? []) {
			final occurrenceSource = OcamlLoweredOrigin.sourceSpan(occurrence.expression.pos);
			if (occurrence.occurrenceId.length == 0
				|| sourceKey(occurrence.source) != sourceKey(occurrenceSource)
				|| !isStatementResultPolicy(occurrence.policy)) {
				throw 'reflaxe.ocaml [ocaml-control:invalid-statement-result]: typed statement-result occurrence has incomplete identity, source, or policy';
			}
			if (indexedStatementResultIds.exists(occurrence.occurrenceId))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-statement-result]: statement-result occurrence "${occurrence.occurrenceId}" appears more than once';
			if (statementResultPolicyByExpression.exists(occurrence.expression))
				throw 'reflaxe.ocaml [ocaml-control:ambiguous-statement-result]: one typed expression has more than one statement-result policy';
			statementResultPolicyByExpression.set(occurrence.expression, occurrence.policy);
			indexedStatementResultIds.set(occurrence.occurrenceId, true);
			normalizedStatementResultFingerprints.push([
				occurrence.occurrenceId,
				sourceKey(occurrence.source),
				(occurrence.policy : String)
			].join("|"));
		}
		normalizedStatementResultFingerprints.sort(Reflect.compare);
		statementResultFingerprints = normalizedStatementResultFingerprints;
		this.admission = admission == null ? null : OcamlControlAdmissionContract.copySnapshot(admission);
		if (this.admission != null) {
			OcamlControlAdmissionContract.requireSnapshot(this.admission);
			if (this.admission.functionId != binding.functionId
				|| this.admission.programRevision != binding.programRevision
				|| this.admission.bodyRevision != binding.bodyRevision
				|| this.admission.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-control-admission:stale-binding]: snapshot "${this.admission.id}" does not belong to function "${binding.functionId}"';
			}
			validateAdmissionFamily(this.admission, OcamlControlAdmissionFamily.Return, returnFamilyAdmitted,
				Lambda.count(ordered, decision -> decision.kind == OcamlControlTransferKind.Return));
			validateAdmissionFamily(this.admission, OcamlControlAdmissionFamily.Loop, loopFamilyAdmitted,
				Lambda.count(ordered, decision -> decision.kind == OcamlControlTransferKind.Break
					|| decision.kind == OcamlControlTransferKind.Continue));
			validateAdmissionFamily(this.admission, OcamlControlAdmissionFamily.Throw, throwFamilyAdmitted,
				Lambda.count(ordered, decision -> decision.kind == OcamlControlTransferKind.Throw));
			if (this.admission.catches.length != catchOccurrenceFingerprints.length
				|| Lambda.count(this.admission.catches, entry -> entry.status == OcamlControlAdmissionStatus.Admitted) != orderedCatchChains.length) {
				throw 'reflaxe.ocaml [ocaml-control-admission:catch-mismatch]: snapshot "${this.admission.id}" disagrees with its admitted and unadmitted catch occurrences';
			}
		}
		revision = "sha256:" + Sha256.encode([
			returnFamilyAdmitted ? "return-admitted" : "return-legacy",
			loopFamilyAdmitted ? "loop-admitted" : "loop-legacy",
			throwFamilyAdmitted ? "throw-admitted" : "throw-legacy",
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			this.admission == null ? "control-admission-unavailable" : this.admission.revision
		].concat(orderedTargets.map(loopTargetFingerprint))
			.concat(ordered.map(decisionFingerprint))
			.concat(orderedCatchChains.map(catchChainFingerprint))
			.concat(catchOccurrenceFingerprints)
			.concat(statementResultFingerprints)
			.join("\n"));
	}

	/** Creates an explicit empty plan for a function outside every control slice. */
	public static function notAdmitted(binding:OcamlFunctionPlanBinding):OcamlControlPlan {
		return new OcamlControlPlan(false, false, false, binding, [], [], null, null, null, null, OcamlControlAdmissionContract.empty(binding));
	}

	/** Returns the detached planner explanation required by deterministic reports. */
	public function admissionSnapshot():OcamlControlAdmissionSnapshot {
		if (admission == null)
			throw 'reflaxe.ocaml [ocaml-control-admission:missing]: function "${binding.functionId}" has no typed control-admission snapshot';
		return OcamlControlAdmissionContract.copySnapshot(admission);
	}

	static function validateAdmissionFamily(snapshot:OcamlControlAdmissionSnapshot, kind:OcamlControlAdmissionFamily, admitted:Bool, decisionCount:Int):Void {
		final family = OcamlControlAdmissionContract.requireFamilyByKind(snapshot, kind);
		if (family.decisionCount != decisionCount
			|| (family.status == OcamlControlAdmissionStatus.Admitted) != (admitted && family.occurrenceCount > 0)
				|| (family.status == OcamlControlAdmissionStatus.Blocked && admitted)) {
			throw 'reflaxe.ocaml [ocaml-control-admission:family-mismatch]: snapshot "${snapshot.id}" disagrees with its $kind plan';
		}
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

	/**
		Returns how many `try` expressions the planner classified, including empty
		or blocked occurrences that have no admitted chain.

		This differs from `catchChains().length`: that list contains only admitted
		catch plans. A caller defining a catch-free slice must also reject an
		unadmitted occurrence, because either form means the function contains a
		`try` expression. Function sealing separately rejects blocked non-empty
		catches before syntax.
	**/
	public function catchOccurrenceCount():Int {
		return catchOccurrenceFingerprints.length;
	}

	/** Whether syntax must install the sealed private return-signal boundary. */
	public function hasReturnTransfers():Bool {
		return Lambda.exists(ordered, decision -> decision.kind == OcamlControlTransferKind.Return);
	}

	/** Whether one loop target owns an admitted break or continue transfer. */
	public function hasTransfersForTarget(targetId:String):Bool {
		return Lambda.exists(ordered, decision -> decision.targetKind == OcamlControlTargetKind.Loop && decision.targetId == targetId);
	}

	/** Returns detached transfer decisions owned by one sealed loop target. */
	public function decisionsForTarget(targetId:String):Array<OcamlControlDecision> {
		final selected = ordered.filter(decision -> decision.targetKind == OcamlControlTargetKind.Loop && decision.targetId == targetId);
		selected.sort((left, right) -> Reflect.compare(left.id, right.id));
		return selected.map(copyDecision);
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
				throw 'reflaxe.ocaml [ocaml-control:missing-catch-disposition]: typed try occurrence has no planned catch disposition';
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

	/**
		Returns the result policies already selected from the final typed `try`.

		Catch matching may still be on the older path, but both paths must use this
		same record when deciding whether a completed branch value is preserved or
		discarded as Haxe `Void`.
	**/
	public function catchBranchResultDispositionFor(expression:TypedExpr):OcamlCatchBranchResultDisposition {
		if (!hasCatchOccurrenceIndex || !catchDispositionByExpression.exists(expression))
			throw 'reflaxe.ocaml [ocaml-control:missing-catch-result-policy]: typed try occurrence has no sealed branch-result policies';
		final disposition = catchBranchResultsByExpression.get(expression);
		if (disposition == null)
			throw 'reflaxe.ocaml [ocaml-control:missing-catch-result-policy]: typed try occurrence lost its sealed branch-result policies';
		return {
			occurrenceId: disposition.occurrenceId,
			tryBodyResultPolicy: disposition.tryBodyResultPolicy,
			clauseBodyResultPolicies: disposition.clauseBodyResultPolicies.copy()
		};
	}

	/** Whether the planner explicitly classified this exact typed `try` node. */
	public function hasCatchDispositionFor(expression:TypedExpr):Bool {
		return hasCatchOccurrenceIndex ? catchDispositionByExpression.exists(expression) : true;
	}

	/** Returns the pre-syntax statement policy for one exact typed expression. */
	public function statementResultPolicyFor(expression:TypedExpr):OcamlStatementResultPolicy {
		if (!hasStatementResultIndex)
			return OcamlStatementResultPolicy.DiscardCompletedValueToUnit;
		final policy = statementResultPolicyByExpression.get(expression);
		if (policy == null)
			throw 'reflaxe.ocaml [ocaml-control:missing-statement-result]: typed statement expression has no sealed result policy';
		return policy;
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
					|| payload.arrayLiteralProducerId != null
					|| payload.arrayLiteralProducerPlanRevision != null
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
					case BoxAndRecoverTypedFunctionResult, BoxBoolAndRecoverDynamicTypedFunctionResult:
						if (!isAdmittedTypedFunctionReturnPayload(payload, decision.functionId)
							|| payload.proofId != TYPED_FUNCTION_RESULT_RETURN_PROOF_ID
							|| decision.proofId != TYPED_FUNCTION_RESULT_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an incomplete typed-function result crossing';
						}
					case PreserveNullableCarrier:
						if ((!isAdmittedNullableSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)
							&& !isExactNullableEnumSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId))
							|| !samePayloadSides(payload)
							|| payload.nominalRepresentation != null
							|| payload.proofId != NULLABLE_CARRIER_RETURN_PROOF_ID
							|| decision.proofId != NULLABLE_CARRIER_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid nullable-carrier payload crossing';
						}
					case PreserveAnonymousCarrier:
						if (!OcamlControlPlan.isAdmittedAnonymousSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)
							|| !samePayloadSides(payload)
							|| payload.nominalRepresentation != null
							|| !isSha256Revision(payload.representationRevision ?? "")
							|| payload.proofId != ANONYMOUS_CARRIER_RETURN_PROOF_ID
							|| decision.proofId != ANONYMOUS_CARRIER_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid anonymous-object carrier crossing';
						}
					case PreserveDynamicReturnCarrier:
						if (!isAdmittedDynamicReturnPayload(payload)
							|| payload.proofId != DYNAMIC_RETURN_PROOF_ID
							|| decision.proofId != DYNAMIC_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid Dynamic carrier crossing';
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
					case BoxExactEnumToNullableCarrier:
						if (!isExactNullableEnumConversion(payload)
							|| payload.nominalRepresentation != null
							|| payload.proofId != NULLABLE_ENUM_CONVERSION_RETURN_PROOF_ID
							|| decision.proofId != NULLABLE_ENUM_CONVERSION_RETURN_PROOF_ID) {
							throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: return decision "${decision.id}" has an invalid enum-to-Null<Enum> payload crossing';
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
		final literalProducerFieldCount = payload == null ? 0 : (payload.arrayLiteralProducerId == null ? 0 : 1)
			+ (payload.arrayLiteralProducerPlanRevision == null ? 0 : 1);
		final hasEnumRepresentation = payload != null && isEnumThrowPayloadIdentity(payload);
		final hasRuntimeClassRepresentation = payload != null && isRuntimeClassThrowPayloadIdentity(payload);
		if (decision.effect != OcamlControlEffect.RaiseHaxeValue
			|| decision.targetKind != OcamlControlTargetKind.HaxeExceptionChannel
			|| decision.targetId != HAXE_EXCEPTION_CHANNEL_ID
			|| decision.mechanism != OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal
			|| decision.runtimeCapabilityId != THROW_SIGNAL_CAPABILITY_ID
			|| payload == null
			|| (literalProducerFieldCount != 0 && (literalProducerFieldCount != 2 || payload.arrayDescriptorId == null))
			|| payload.signalCarrierTypeId != "Obj.t"
			|| !samePayloadSides(payload)
			|| payload.conversion != expectedThrowConversion(payload.inputSemanticTypeId, payload.nominalRepresentation != null, hasEnumRepresentation,
				payload.arrayDescriptorId != null, hasRuntimeClassRepresentation)
			|| payload.proofClaim.length == 0
			|| !sameStrings(decision.runtimeTags,
				expectedThrowTags(payload.inputSemanticTypeId, payload.nominalRepresentation != null, hasEnumRepresentation,
					payload.arrayDescriptorId != null, hasRuntimeClassRepresentation))
			|| decision.runtimeTagPolicy != OcamlControlRuntimeTagPolicy.MergeDynamicWithExactRuntimeValue) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an unsupported exception target or incomplete value payload crossing';
		}

		final hasNominalRepresentation = payload.nominalRepresentation != null;
		final expectedProofId = expectedThrowProofId(payload.inputSemanticTypeId, hasNominalRepresentation, hasEnumRepresentation,
			payload.arrayDescriptorId != null, hasRuntimeClassRepresentation);
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
			case BoxRepresentedArrayThrowCarrier:
				if (!isAdmittedRepresentedArrayThrowPayload(payload)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid represented-array exception crossing';
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
			case BoxEnumThrowCarrier:
				if (!isAdmittedEnumThrowPayload(payload)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid direct enum-constructor carrier crossing';
				}
			case BoxRuntimeClassThrowCarrier:
				if (!isAdmittedRuntimeClassThrowPayload(payload)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: throw decision "${decision.id}" has an invalid runtime-tagged class carrier crossing';
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
			case "Float":
				requireExactCatchSide(clause, "float", "representation:Float:internal-value", "Float", OcamlCatchPayloadConversion.RecoverExactValue);
			case "Bool":
				requireExactCatchSide(clause, "bool", "representation:Bool:internal-value", "Bool", OcamlCatchPayloadConversion.RecoverCheckedBool);
			case "String":
				requireExactCatchSide(clause, "string", "representation:String:internal-value", "String", OcamlCatchPayloadConversion.RecoverExactValue);
			case _ if (clause.nominalRepresentation != null):
				if (!isAdmittedNominalCatchClause(clause)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: nominal catch clause "${clause.id}" has an invalid tag, carrier, representation, conversion, or layout proof';
				}
			case _ if (StringTools.startsWith(clause.outputRepresentationId, ENUM_CATCH_CONTROL_REPRESENTATION_PREFIX)):
				if (!isAdmittedEnumCatchClause(clause)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: enum catch clause "${clause.id}" has an invalid tag, carrier, representation, or conversion';
				}
			case _ if (StringTools.startsWith(clause.outputRepresentationId, RUNTIME_CLASS_CATCH_CONTROL_REPRESENTATION_PREFIX)):
				if (!isAdmittedRuntimeClassCatchClause(clause)) {
					throw 'reflaxe.ocaml [ocaml-control:invalid-catch-clause]: runtime-tagged class catch clause "${clause.id}" has an invalid tag, carrier, representation, or conversion';
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

	static function isStatementResultPolicy(policy:OcamlStatementResultPolicy):Bool {
		return policy == OcamlStatementResultPolicy.PreserveNonLocalResult
			|| policy == OcamlStatementResultPolicy.DiscardCompletedValueToUnit;
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
			representationRevision: payload.representationRevision,
			arrayDescriptorId: payload.arrayDescriptorId,
			arrayDescriptorRevision: payload.arrayDescriptorRevision,
			arrayLiteralProducerId: payload.arrayLiteralProducerId,
			arrayLiteralProducerPlanRevision: payload.arrayLiteralProducerPlanRevision,
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

	/** Recognizes a nullable carrier whose exact enum owner is checked separately. */
	public static function isExactNullableEnumSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return StringTools.startsWith(semanticTypeId, "Null<")
			&& StringTools.endsWith(semanticTypeId, ">")
			&& carrierTypeId == "Obj.t"
			&& representationId == 'representation:$semanticTypeId:internal-value';
	}

	/** Whether one side is the exact carrier selected for a sealed anonymous shape. */
	public static function isAdmittedAnonymousSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return StringTools.startsWith(semanticTypeId, "anonymous{")
			&& StringTools.endsWith(semanticTypeId, "}")
			&& carrierTypeId == "Obj.t"
			&& representationId == 'representation:$semanticTypeId:internal-value';
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

	static function isExactNullableEnumConversion(payload:OcamlControlPayloadPlan):Bool {
		return payload.inputSemanticTypeId.length > 0
			&& payload.inputCarrierTypeId == '${OcamlEnumDynamicCarrier.CARRIER_MODEL}:${payload.inputSemanticTypeId}'
			&& payload.inputRepresentationId == 'representation:${payload.inputSemanticTypeId}:internal-value'
			&& payload.signalCarrierTypeId == "Obj.t"
			&& payload.outputSemanticTypeId == 'Null<${payload.inputSemanticTypeId}>'
			&& payload.outputCarrierTypeId == "Obj.t"
			&& payload.outputRepresentationId == 'representation:${payload.outputSemanticTypeId}:internal-value'
			&& payload.representationRevision == null;
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

	/** Reports whether one exact ordinary Haxe enum catch preserves its native variant carrier. */
	public static function isAdmittedEnumCatchClause(clause:OcamlCatchClauseDecision):Bool {
		final expectedCarrier = OcamlEnumDynamicCarrier.CARRIER_MODEL + ":" + clause.semanticTypeId;
		return clause.semanticTypeId.length > 0
			&& clause.outputCarrierTypeId == expectedCarrier
			&& clause.outputRepresentationId == ENUM_CATCH_CONTROL_REPRESENTATION_PREFIX + clause.semanticTypeId
			&& clause.matchPolicy == OcamlCatchMatchPolicy.ExactRuntimeTag
			&& clause.runtimeTag == clause.semanticTypeId
			&& clause.conversion == OcamlCatchPayloadConversion.RecoverEnumValue
			&& clause.nominalRepresentation == null;
	}

	/**
		Reports whether a generated class catch uses the private runtime-tag carrier.

		The runtime tag check happens before syntax converts `Obj.t` to the catch
		variable type. This order makes superclass matching safe without claiming
		that unrelated generated class records share one public representation.
	**/
	public static function isAdmittedRuntimeClassCatchClause(clause:OcamlCatchClauseDecision):Bool {
		return clause.semanticTypeId.length > 0
			&& clause.outputCarrierTypeId == RUNTIME_CLASS_CARRIER_PREFIX + clause.semanticTypeId
			&& clause.outputRepresentationId == RUNTIME_CLASS_CATCH_CONTROL_REPRESENTATION_PREFIX + clause.semanticTypeId
			&& clause.matchPolicy == OcamlCatchMatchPolicy.ExactRuntimeTag
			&& clause.runtimeTag == clause.semanticTypeId
			&& clause.conversion == OcamlCatchPayloadConversion.RecoverRuntimeClassValue
			&& clause.nominalRepresentation == null;
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

	public static function expectedThrowTags(semanticTypeId:String, hasNominalRepresentation:Bool = false, hasEnumRepresentation:Bool = false,
			hasRepresentedArray:Bool = false, hasRuntimeClassRepresentation:Bool = false):Array<String> {
		if (hasRepresentedArray)
			return ["Dynamic", "Array"];
		if (hasRuntimeClassRepresentation)
			return ["Dynamic"];
		return switch (semanticTypeId) {
			case "Int", "Bool", "String", "Null<Int>", "Null<Bool>", "Dynamic", "haxe.Exception", "haxe.ValueException": ["Dynamic"];
			case _: hasEnumRepresentation ? ["Dynamic", semanticTypeId] : (hasNominalRepresentation ? ["Dynamic"] : []);
		}
	}

	public static function expectedThrowConversion(semanticTypeId:String, hasNominalRepresentation:Bool = false, hasEnumRepresentation:Bool = false,
			hasRepresentedArray:Bool = false, hasRuntimeClassRepresentation:Bool = false):Null<OcamlControlPayloadConversion> {
		if (hasRepresentedArray)
			return OcamlControlPayloadConversion.BoxRepresentedArrayThrowCarrier;
		if (hasRuntimeClassRepresentation)
			return OcamlControlPayloadConversion.BoxRuntimeClassThrowCarrier;
		return switch (semanticTypeId) {
			case "Int", "String": OcamlControlPayloadConversion.ReprAndRecoverExactValue;
			case "Bool": OcamlControlPayloadConversion.BoxBoolAndRecoverExactValue;
			case "Null<Int>": OcamlControlPayloadConversion.PreserveNullableIntThrowCarrier;
			case "Null<Bool>": OcamlControlPayloadConversion.NormalizeNullableBoolThrowCarrier;
			case "Dynamic": OcamlControlPayloadConversion.PreserveDynamicThrowCarrier;
			case "haxe.Exception", "haxe.ValueException": OcamlControlPayloadConversion.BoxHaxeExceptionWrapperThrowCarrier;
			case _: hasEnumRepresentation ? OcamlControlPayloadConversion.BoxEnumThrowCarrier : (hasNominalRepresentation ? OcamlControlPayloadConversion.BoxNominalThrowCarrier : null);
		}
	}

	/** Selects the proof family required by one admitted throw payload. */
	public static function expectedThrowProofId(semanticTypeId:String, hasNominalRepresentation:Bool = false, hasEnumRepresentation:Bool = false,
			hasRepresentedArray:Bool = false, hasRuntimeClassRepresentation:Bool = false):Null<String> {
		if (hasRepresentedArray)
			return REPRESENTED_ARRAY_THROW_PROOF_ID;
		if (hasRuntimeClassRepresentation)
			return RUNTIME_CLASS_THROW_PROOF_ID;
		return switch (semanticTypeId) {
			case "Int", "Bool", "String": EXACT_VALUE_THROW_PROOF_ID;
			case "Null<Int>": NULLABLE_INT_THROW_PROOF_ID;
			case "Null<Bool>": NULLABLE_BOOL_THROW_PROOF_ID;
			case "Dynamic": DYNAMIC_THROW_PROOF_ID;
			case "haxe.Exception", "haxe.ValueException": HAXE_EXCEPTION_WRAPPER_THROW_PROOF_ID;
			case _: hasEnumRepresentation ? EXACT_ENUM_THROW_PROOF_ID : (hasNominalRepresentation ? EXACT_NOMINAL_THROW_PROOF_ID : null);
		}
	}

	/** Returns the control-only representation identity for one direct enum throw. */
	public static function enumThrowRepresentationId(semanticTypeId:String):String {
		return ENUM_THROW_CONTROL_REPRESENTATION_PREFIX + semanticTypeId;
	}

	/** Returns the catch-only representation identity for one ordinary Haxe enum. */
	public static function enumCatchRepresentationId(semanticTypeId:String):String {
		return ENUM_CATCH_CONTROL_REPRESENTATION_PREFIX + semanticTypeId;
	}

	/** Returns the control-only identity for a non-generic generated class. */
	public static function runtimeClassCarrierIdentityForType(type:Type):Null<OcamlRuntimeClassCarrierIdentity> {
		return switch (haxe.macro.TypeTools.follow(type)) {
			case TInst(classRef, parameters):
				final classType = classRef.get();
				if (classType.isExtern || classType.isInterface || parameters.length != 0 || haxeExceptionWrapperTypeId(type) != null) {
					null;
				} else {
					final semanticTypeId = (classType.pack ?? []).concat([classType.name]).join(".");
					semanticTypeId.length == 0 ? null : {
						semanticTypeId: semanticTypeId,
						carrierTypeId: RUNTIME_CLASS_CARRIER_PREFIX + semanticTypeId,
						throwRepresentationId: RUNTIME_CLASS_THROW_CONTROL_REPRESENTATION_PREFIX + semanticTypeId,
						catchRepresentationId: RUNTIME_CLASS_CATCH_CONTROL_REPRESENTATION_PREFIX + semanticTypeId
					};
				}
			case _:
				null;
		};
	}

	/**
		Checks the complete control-only carrier for one visible enum constructor.

		This does not register a reusable whole-program enum representation. It
		only proves that a native variant with the sealed Haxe enum name can be
		wrapped once while it crosses the private exception channel.
	**/
	public static function isAdmittedEnumThrowPayload(payload:OcamlControlPayloadPlan):Bool {
		return isEnumThrowPayloadIdentity(payload)
			&& payload.conversion == OcamlControlPayloadConversion.BoxEnumThrowCarrier
			&& payload.signalCarrierTypeId == "Obj.t"
			&& payload.nominalRepresentation == null;
	}

	/** Reports whether one generated class crosses only the exception channel. */
	public static function isAdmittedRuntimeClassThrowPayload(payload:OcamlControlPayloadPlan):Bool {
		return isRuntimeClassThrowPayloadIdentity(payload)
			&& payload.signalCarrierTypeId == "Obj.t"
			&& payload.conversion == OcamlControlPayloadConversion.BoxRuntimeClassThrowCarrier
			&& payload.nominalRepresentation == null
			&& payload.representationRevision == null
			&& payload.arrayDescriptorId == null
			&& payload.arrayDescriptorRevision == null
			&& payload.arrayLiteralProducerId == null
			&& payload.arrayLiteralProducerPlanRevision == null;
	}

	static function isRuntimeClassThrowPayloadIdentity(payload:OcamlControlPayloadPlan):Bool {
		return payload.inputSemanticTypeId.length > 0
			&& payload.inputCarrierTypeId == RUNTIME_CLASS_CARRIER_PREFIX + payload.inputSemanticTypeId
			&& payload.inputRepresentationId == RUNTIME_CLASS_THROW_CONTROL_REPRESENTATION_PREFIX + payload.inputSemanticTypeId
			&& samePayloadSides(payload);
	}

	static function isEnumThrowPayloadIdentity(payload:OcamlControlPayloadPlan):Bool {
		if (payload.inputSemanticTypeId.length == 0
			|| payload.outputSemanticTypeId != payload.inputSemanticTypeId
			|| payload.outputCarrierTypeId != payload.inputCarrierTypeId
			|| payload.outputRepresentationId != payload.inputRepresentationId
			|| payload.inputRepresentationId != enumThrowRepresentationId(payload.inputSemanticTypeId)) {
			return false;
		}
		return try {
			OcamlEnumDynamicCarrier.requireIdentity(payload.inputSemanticTypeId, payload.inputCarrierTypeId);
			true;
		} catch (_:Dynamic) {
			false;
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
		Reports whether one descriptor-backed array keeps its native object while
		crossing the private Haxe exception channel.

		A represented-array descriptor is the immutable record that binds an exact
		Haxe array shape to its element representation and `HxArray.t` carrier.
		`Obj.t` is only the opaque in-flight exception carrier, so a Dynamic catch
		receives the same mutable array object. `Array<Int>` may arrive through the
		already-proved local or literal route. `Array<String>` is narrower: it must
		name a complete direct-literal producer, so recognizing its source shape
		cannot admit String-array locals, fields, calls, returns, or ABI crossings.
	**/
	public static function isAdmittedRepresentedArrayThrowPayload(payload:OcamlControlPayloadPlan):Bool {
		final producerFieldCount = (payload.arrayLiteralProducerId == null ? 0 : 1) + (payload.arrayLiteralProducerPlanRevision == null ? 0 : 1);
		final familyAdmitted = switch (payload.inputSemanticTypeId) {
			case "Array<Int>": payload.inputCarrierTypeId == "int HxArray.t" && (producerFieldCount == 0 || producerFieldCount == 2);
			case "Array<String>": payload.inputCarrierTypeId == "string HxArray.t" && producerFieldCount == 2;
			case _: false;
		};
		return familyAdmitted
			&& payload.inputRepresentationId == 'representation:${payload.inputSemanticTypeId}:internal-value'
			&& isSha256Revision(payload.representationRevision ?? "")
			&& payload.arrayDescriptorId == 'represented-array:${payload.inputSemanticTypeId}'
			&& isSha256Revision(payload.arrayDescriptorRevision ?? "")
			&& payload.signalCarrierTypeId == "Obj.t"
			&& samePayloadSides(payload)
			&& payload.conversion == OcamlControlPayloadConversion.BoxRepresentedArrayThrowCarrier
			&& payload.nominalRepresentation == null
			&& (producerFieldCount == 0
				|| (producerFieldCount == 2
					&& StringTools.startsWith(payload.arrayLiteralProducerId, "array-literal-producer:")
					&& isSha256Revision(payload.arrayLiteralProducerPlanRevision)));
	}

	/**
		Reports whether an existing Dynamic value crosses a function return unchanged.

		Dynamic uses `Obj.t` as its normal internal target representation. The private
		return signal also carries `Obj.t`, so an admitted return neither boxes the value
		again nor guesses its concrete runtime type while printing OCaml syntax.
	**/
	public static function isAdmittedDynamicReturnPayload(payload:OcamlControlPayloadPlan):Bool {
		return payload.inputSemanticTypeId == "Dynamic"
			&& payload.inputCarrierTypeId == "Obj.t"
			&& payload.inputRepresentationId == "representation:Dynamic:internal-value"
			&& payload.signalCarrierTypeId == "Obj.t"
			&& payload.outputSemanticTypeId == "Dynamic"
			&& payload.outputCarrierTypeId == "Obj.t"
			&& payload.outputRepresentationId == "representation:Dynamic:internal-value"
			&& payload.conversion == OcamlControlPayloadConversion.PreserveDynamicReturnCarrier
			&& payload.nominalRepresentation == null;
	}

	/**
		Reports whether one private return uses its exact Haxe-typed function owner.

		The carrier name is a policy marker, not an OCaml type. `Obj.t` exists only
		while the private exception is in flight. The matching function handler uses
		OCaml type inference to recover the value into the same function body, so the
		plan does not invent a callable carrier or use `Obj.magic` as evidence.
	**/
	public static function isAdmittedTypedFunctionReturnPayload(payload:OcamlControlPayloadPlan, functionId:String):Bool {
		final needsTaggedBoolBox = payload.inputSemanticTypeId == "Bool" && payload.outputSemanticTypeId == "Dynamic";
		final conversionAdmitted = needsTaggedBoolBox ? payload.conversion == OcamlControlPayloadConversion.BoxBoolAndRecoverDynamicTypedFunctionResult : payload.conversion == OcamlControlPayloadConversion.BoxAndRecoverTypedFunctionResult;
		return conversionAdmitted
			&& payload.inputSemanticTypeId.length > 0
			&& payload.outputSemanticTypeId.length > 0
			&& payload.inputCarrierTypeId == OcamlTypedFunctionResultBoundary.INFERRED_CARRIER_TYPE_ID
			&& payload.outputCarrierTypeId == OcamlTypedFunctionResultBoundary.INFERRED_CARRIER_TYPE_ID
			&& payload.inputRepresentationId == OcamlTypedFunctionResultBoundary.representationId(functionId, "input", payload.inputSemanticTypeId)
			&& payload.outputRepresentationId == OcamlTypedFunctionResultBoundary.representationId(functionId, "output", payload.outputSemanticTypeId)
			&& payload.signalCarrierTypeId == "Obj.t"
			&& payload.representationRevision == null
			&& payload.arrayDescriptorId == null
			&& payload.arrayDescriptorRevision == null
			&& payload.arrayLiteralProducerId == null
			&& payload.arrayLiteralProducerPlanRevision == null
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
		if (payload.conversion == OcamlControlPayloadConversion.BoxAndRecoverTypedFunctionResult
			|| payload.conversion == OcamlControlPayloadConversion.BoxBoolAndRecoverDynamicTypedFunctionResult) {
			return haxe.macro.TypeTools.toString(expression.t) == payload.inputSemanticTypeId;
		}
		if (payload.conversion == OcamlControlPayloadConversion.PreserveAnonymousCarrier) {
			final unwrapped = unwrapControlTransparent(expression);
			return switch (unwrapped.expr) {
				case TConst(TNull): OcamlAnonymousStructurePlan.semanticTypeIdForType(unwrapped.t) == payload.inputSemanticTypeId && isAdmittedAnonymousSide(payload.inputSemanticTypeId,
						payload.inputCarrierTypeId, payload.inputRepresentationId);
				case _: false;
			};
		}
		if (payload.conversion == OcamlControlPayloadConversion.PreserveNullableCarrier
			&& isExactNullableEnumSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)) {
			final unwrapped = unwrapControlTransparent(expression);
			return switch (unwrapped.expr) {
				case TConst(TNull): haxe.macro.TypeTools.toString(unwrapped.t) == payload.inputSemanticTypeId;
				case _: false;
			};
		}
		if (payload.conversion == OcamlControlPayloadConversion.BoxExactEnumToNullableCarrier) {
			final identity = exactEnumReturnIdentity(expression);
			return identity != null
				&& identity.semanticTypeId == payload.inputSemanticTypeId
				&& identity.carrierTypeId == payload.inputCarrierTypeId
				&& isExactNullableEnumConversion(payload);
		}
		if (isAdmittedEnumThrowPayload(payload)) {
			final identity = OcamlEnumDynamicCarrier.fromDirectValue(expression);
			return identity != null
				&& identity.semanticTypeId == payload.inputSemanticTypeId
				&& identity.carrierTypeId == payload.inputCarrierTypeId;
		}
		if (isAdmittedRuntimeClassThrowPayload(payload)) {
			final identity = runtimeClassCarrierIdentityForType(expression.t);
			return identity != null
				&& identity.semanticTypeId == payload.inputSemanticTypeId
				&& identity.carrierTypeId == payload.inputCarrierTypeId
				&& identity.throwRepresentationId == payload.inputRepresentationId;
		}
		if (payload.arrayDescriptorId != null) {
			final hasLiteralProducer = payload.arrayLiteralProducerId != null && payload.arrayLiteralProducerPlanRevision != null;
			final normalized = if (hasLiteralProducer) {
				switch (expression.expr) {
					case TArrayDecl(_): OcamlDirectArraySourceIdentity.normalize(expression.t);
					case _: null;
				}
			} else {
				OcamlRepresentationRegistry.normalizedDirectFlatArray(expression.t);
			};
			return normalized != null
				&& normalized.arraySemanticTypeId == payload.inputSemanticTypeId
				&& isAdmittedRepresentedArrayThrowPayload(payload);
		}
		return switch (payload.inputSemanticTypeId) {
			case "Int": OcamlRepresentationRegistry.isExactInt(expression.t);
			case "Bool": OcamlRepresentationRegistry.isExactBool(expression.t);
			case "Null<Int>": OcamlRepresentationRegistry.isExactNullInt(expression.t);
			case "Null<Bool>": OcamlRepresentationRegistry.isExactNullBool(expression.t);
			case "String": OcamlRepresentationRegistry.isExactString(expression.t);
			case "Dynamic":
				switch (haxe.macro.TypeTools.follow(expression.t)) {
					case TDynamic(_): isAdmittedDynamicReturnPayload(payload) || isAdmittedDynamicThrowPayload(payload);
					case _:
						false;
				}
			case "haxe.Exception",
				"haxe.ValueException": haxeExceptionWrapperTypeId(expression.t) == payload.inputSemanticTypeId && isAdmittedHaxeExceptionThrowPayload(payload);
			case _: final semanticTypeId = OcamlRepresentationRegistry.monomorphicClassSemanticTypeId(expression.t); (payload.conversion == OcamlControlPayloadConversion.BoxAndRecoverNominalValue
					|| payload.conversion == OcamlControlPayloadConversion.BoxNominalThrowCarrier) && semanticTypeId == payload.inputSemanticTypeId && isAdmittedNominalPayload(payload);
		}
	}

	static function unwrapControlTransparent(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, child), TParenthesis(child): unwrapControlTransparent(child);
			case _: expression;
		};
	}

	/**
		Returns the exact enum identity only when this return reads a typed local or
		constructs the enum at the return site.

		The function result boundary proves how that exact enum enters `Null<Enum>`.
		It does not yet prove arbitrary field reads or function-call results, even if
		the Haxe type checker gives those expressions the same enum type.
	**/
	public static function exactEnumReturnIdentity(expression:TypedExpr):Null<OcamlEnumDynamicCarrierIdentity> {
		final direct = OcamlEnumDynamicCarrier.fromDirectValue(expression);
		if (direct != null)
			return direct;
		final unwrapped = unwrapControlTransparent(expression);
		return switch (unwrapped.expr) {
			case TLocal(_): OcamlEnumDynamicCarrier.fromType(unwrapped.t);
			case _: null;
		};
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
			case "Float": OcamlRepresentationRegistry.isExactFloat(type);
			case "Bool": OcamlRepresentationRegistry.isExactBool(type);
			case "String": OcamlRepresentationRegistry.isExactString(type);
			case "Dynamic":
				switch (haxe.macro.TypeTools.follow(type)) {
					case TDynamic(_): true;
					case _: false;
				}
			case "haxe.Exception",
				"haxe.ValueException": haxeExceptionWrapperTypeId(type) == clause.semanticTypeId && isAdmittedHaxeExceptionCatchClause(clause);
			case _:
				final enumIdentity = OcamlEnumDynamicCarrier.fromType(type);
				if (enumIdentity != null) {
					enumIdentity.semanticTypeId == clause.semanticTypeId
					&& enumIdentity.carrierTypeId == clause.outputCarrierTypeId
					&& isAdmittedEnumCatchClause(clause);
				} else if (StringTools.startsWith(clause.outputRepresentationId, RUNTIME_CLASS_CATCH_CONTROL_REPRESENTATION_PREFIX)) {
					final identity = runtimeClassCarrierIdentityForType(type);
					identity != null
					&& identity.semanticTypeId == clause.semanticTypeId
					&& identity.carrierTypeId == clause.outputCarrierTypeId
					&& identity.catchRepresentationId == clause.outputRepresentationId
					&& isAdmittedRuntimeClassCatchClause(clause);
				} else {
					final semanticTypeId = OcamlRepresentationRegistry.monomorphicClassSemanticTypeId(type);
					semanticTypeId != null && semanticTypeId == clause.semanticTypeId && isAdmittedNominalCatchClause(clause)
					;
				}
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
			payload.representationRevision ?? "",
			payload.arrayDescriptorId ?? "",
			payload.arrayDescriptorRevision ?? "",
			payload.arrayLiteralProducerId ?? "",
			payload.arrayLiteralProducerPlanRevision ?? "",
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
	Plans non-local control before the OCaml syntax builder runs.

	For a return, the planner first uses a precise represented result when one is
	available. If one return in a value-producing function cannot use that result,
	the planner gives every return in that function one owner-bound fallback. This
	fallback uses the result type that Haxe already checked. It does not define a
	public call representation. An effect-only `Void` function uses a payloadless
	private signal.

	Loop admission is independent and records `while` and `do ... while` targets
	in every sealed function body. Throw admission is also independent. It accepts exact
	`Int`, `Bool`, represented `String`, `Null<Int>`, `Null<Bool>`, one exact
	immutable-local `Array<Int>` or directly constructed `Array<Int>`/`Array<String>`, one whole-program-monomorphic class payload, or
	a directly visible ordinary enum constructor. The array case reuses the
	already-sealed descriptor-backed `HxArray.t` value. A direct literal is admitted only when a
	separate producer plan has fixed its container creation and element evaluation
	order; control does not reconstruct that work. Fields, calls, and generic arrays
	remain unsupported. A direct enum throw means the thrown expression
	itself is the constructor value or call; values reached through locals, casts,
	fields, or other expressions remain outside this slice. Nested function literals own
	independent boundaries and are deliberately skipped. Each source `try` is
	admitted independently. Thus, one unsupported catch chain does not discard
	another represented chain in the same function.

	Stable record IDs use the node's structural path through the final typed body,
	not its source span. Haxe-generated nodes can legitimately share `(unknown):0`
	or another copied position; source spans remain diagnostics, while a private
	request-local object index reconnects each stable record to the exact immutable
	node consumed by syntax generation.
**/
private typedef OcamlObservedReturn = {
	final expression:TypedExpr;
	final value:Null<TypedExpr>;
	final path:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:Null<String>;
}

class OcamlControlPlanner {
	final representations:OcamlRepresentationRegistry;
	final localRepresentations:OcamlLocalRepresentationPlan;
	final binding:OcamlFunctionPlanBinding;
	final localIdentities:LexicalLocalIdentityPlan;
	final arrayLiteralProducers:OcamlArrayLiteralProducerPlan;
	final nominalCatchRepresentations:Map<Int, OcamlRepresentationDecision> = [];

	public function new(representations:OcamlRepresentationRegistry, localRepresentations:OcamlLocalRepresentationPlan, binding:OcamlFunctionPlanBinding,
			localIdentities:LexicalLocalIdentityPlan, ?arrayLiteralProducers:OcamlArrayLiteralProducerPlan) {
		this.representations = representations;
		this.localRepresentations = localRepresentations;
		this.binding = binding;
		this.localIdentities = localIdentities;
		this.arrayLiteralProducers = arrayLiteralProducers ?? new OcamlArrayLiteralProducerPlan([]);
	}

	public function plan(body:Null<TypedExpr>, boundary:Null<OcamlFunctionResultBoundaryPlan>,
			?typedBoundary:OcamlTypedFunctionResultBoundaryPlan):OcamlControlPlan {
		if (body == null)
			return OcamlControlPlan.notAdmitted(binding);
		if (typedBoundary != null)
			OcamlTypedFunctionResultBoundary.require(typedBoundary, binding);

		final boundaryPayload = admittedBoundaryPayload(boundary);
		final effectOnlyVoidBoundary = admittedEffectOnlyVoidBoundary(boundary)
			|| typedBoundary != null
			&& typedBoundary.resultKind == OcamlCallResultKind.EffectOnlyVoid;
		final typedValueBoundary = typedBoundary != null && typedBoundary.resultKind == OcamlCallResultKind.Value;
		final preciseReturnBoundaryAdmitted = boundaryPayload != null || effectOnlyVoidBoundary;
		final returnBoundaryAdmitted = preciseReturnBoundaryAdmitted || typedValueBoundary;
		var returnFamilyAdmitted = returnBoundaryAdmitted;
		var typedValueFallbackRequired = false;
		var loopFamilyAdmitted = true;
		var throwFamilyAdmitted = true;
		var returnOccurrenceCount = 0;
		var loopOccurrenceCount = 0;
		var throwOccurrenceCount = 0;
		final returnBlockers:Array<OcamlControlAdmissionBlocker> = [];
		final loopBlockers:Array<OcamlControlAdmissionBlocker> = [];
		final throwBlockers:Array<OcamlControlAdmissionBlocker> = [];
		final targets:Array<OcamlControlLoopTarget> = [];
		var decisions:Array<OcamlControlDecision> = [];
		final catchChains:Array<OcamlCatchChainDecision> = [];
		final targetOccurrences:Array<OcamlControlLoopTargetOccurrence> = [];
		var decisionOccurrences:Array<OcamlControlDecisionOccurrence> = [];
		final catchOccurrences:Array<OcamlCatchChainOccurrence> = [];
		final statementResultOccurrences:Array<OcamlStatementResultOccurrence> = [];
		final catchAdmissions:Array<OcamlControlCatchAdmission> = [];
		final loopStack:Array<OcamlControlLoopTarget> = [];
		final observedReturns:Array<OcamlObservedReturn> = [];

		function addStatementResult(expression:TypedExpr, path:String):Void {
			statementResultOccurrences.push({
				expression: expression,
				occurrenceId: statementResultOccurrenceId(path),
				source: OcamlLoweredOrigin.sourceSpan(expression.pos),
				policy: OcamlControlFlowFacts.definitelyReturnsOrThrows(expression) ? OcamlStatementResultPolicy.PreserveNonLocalResult : OcamlStatementResultPolicy.DiscardCompletedValueToUnit
			});
		}

		function observeStatementResults(expression:TypedExpr, path:String):Void {
			switch (expression.expr) {
				case TIf(_, thenExpression, elseExpression):
					if (elseExpression == null || isVoid(expression.t))
						addStatementResult(thenExpression, path + "/if:then");
					if (elseExpression != null && isVoid(expression.t))
						addStatementResult(elseExpression, path + "/if:else");
				case TSwitch(_, cases, defaultExpression) if (isVoid(expression.t)):
					for (index => entry in cases)
						addStatementResult(entry.expr, path + "/switch:case:" + index);
					if (defaultExpression != null)
						addStatementResult(defaultExpression, path + "/switch:default");
				case _:
			}
		}

		function addLoopTransfer(expression:TypedExpr, path:String, kind:OcamlControlTransferKind):Void {
			loopOccurrenceCount++;
			if (loopStack.length == 0) {
				loopFamilyAdmitted = false;
				loopBlockers.push(OcamlControlAdmissionContract.blocker("loop-target-missing", controlBlockerOccurrenceId(kind, path),
					OcamlLoweredOrigin.sourceSpan(expression.pos)));
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
			observeStatementResults(expression, path);
			switch (expression.expr) {
				case TReturn(value):
					if (value != null)
						visit(value, false, path + "/return-value");
					if (directRootStatement)
						return;
					returnOccurrenceCount++;
					final returnSource = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final returnSemanticTypeId = value == null ? null : haxe.macro.TypeTools.toString(value.t);
					final returnOccurrenceId = controlBlockerOccurrenceId(OcamlControlTransferKind.Return, path);
					observedReturns.push({
						expression: expression,
						value: value,
						path: path,
						source: returnSource,
						semanticTypeId: returnSemanticTypeId
					});
					if (!preciseReturnBoundaryAdmitted) {
						if (typedValueBoundary && value != null) {
							typedValueFallbackRequired = true;
							return;
						}
						returnFamilyAdmitted = false;
						if (!returnBoundaryAdmitted && returnBlockers.length == 0) {
							returnBlockers.push(OcamlControlAdmissionContract.blocker("return-boundary-unrepresented", returnOccurrenceId, returnSource,
								returnSemanticTypeId));
						}
						return;
					}
					if (value == null && effectOnlyVoidBoundary) {
						final proofClaim = 'The final typed Haxe body assigns this payloadless return to the current effect-only Void function. The private payloadless runtime signal exits only that exact function boundary and does not invent a Haxe value, carrier, or representation.';
						final decision:OcamlControlDecision = {
							id: controlId(OcamlControlTransferKind.Return, path, binding.functionId),
							source: returnSource,
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
					if (value == null) {
						returnFamilyAdmitted = false;
						returnBlockers.push(OcamlControlAdmissionContract.blocker("return-payload-missing", returnOccurrenceId, returnSource));
						return;
					}
					final representation = value == null ? null : returnRepresentation(value, boundary);
					final payload = representation == null ? null : returnPayload(representation, boundaryPayload);
					if (representation == null) {
						if (typedValueBoundary) {
							typedValueFallbackRequired = true;
						} else {
							returnFamilyAdmitted = false;
							returnBlockers.push(OcamlControlAdmissionContract.blocker("return-value-unrepresented", returnOccurrenceId, returnSource,
								returnSemanticTypeId));
						}
						return;
					}
					if (payload == null) {
						if (typedValueBoundary) {
							typedValueFallbackRequired = true;
						} else {
							returnFamilyAdmitted = false;
							returnBlockers.push(OcamlControlAdmissionContract.blocker("return-conversion-unrepresented", returnOccurrenceId, returnSource,
								returnSemanticTypeId));
						}
						return;
					}
					final proofId = payload.proofId;
					final proofClaim = payload.proofClaim;
					final decision:OcamlControlDecision = {
						id: controlId(OcamlControlTransferKind.Return, path, binding.functionId),
						source: returnSource,
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
					throwOccurrenceCount++;
					visit(value, false, path + "/throw-value");
					final throwSource = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final throwSemanticTypeId = haxe.macro.TypeTools.toString(value.t);
					final throwOccurrenceId = controlBlockerOccurrenceId(OcamlControlTransferKind.Throw, path);
					final representation = throwRepresentation(value);
					final nominalRepresentation = representation == null ? null : representation.nominalRepresentation;
					final enumRepresentation = representation != null && representation.enumIdentity != null;
					final representedArray = representation != null && representation.arrayDescriptorId != null;
					final runtimeClassRepresentation = representation != null && representation.runtimeClassIdentity != null;
					final conversion = representation == null ? null : OcamlControlPlan.expectedThrowConversion(representation.semanticTypeId,
						nominalRepresentation != null, enumRepresentation, representedArray, runtimeClassRepresentation);
					if (representation == null || conversion == null) {
						throwFamilyAdmitted = false;
						throwBlockers.push(OcamlControlAdmissionContract.blocker(representation == null ? "throw-value-unrepresented" : "throw-conversion-unrepresented",
							throwOccurrenceId, throwSource,
							throwSemanticTypeId));
						return;
					}
					final proofId = OcamlControlPlan.expectedThrowProofId(representation.semanticTypeId, nominalRepresentation != null, enumRepresentation,
						representedArray, runtimeClassRepresentation);
					if (proofId == null) {
						throwFamilyAdmitted = false;
						throwBlockers.push(OcamlControlAdmissionContract.blocker("throw-proof-unrepresented", throwOccurrenceId, throwSource,
							throwSemanticTypeId));
						return;
					}
					final proofClaim = if (representedArray && representation.arrayLiteralProducerId != null) {
						'The final typed Haxe body throws one directly constructed ${representation.semanticTypeId}/${representation.carrierTypeId} value through the compiler-owned Haxe exception channel. Producer ${representation.arrayLiteralProducerId} fixes container creation, ordered element evaluation, and one store per element before control consumes the finished array. The representation and array-descriptor revisions preserve that same mutable array object; Obj.t is only the in-flight carrier, and the runtime tags identify the value as Dynamic and Array without admitting another array boundary.';
					} else if (representedArray) {
						'The final typed Haxe body throws one already-sealed ${representation.semanticTypeId}/${representation.carrierTypeId} local through the compiler-owned Haxe exception channel. The representation and array-descriptor revisions preserve the same mutable array object; Obj.t is only the in-flight carrier, and the runtime tags identify the value as Dynamic and Array without admitting another array boundary.';
					} else switch (representation.semanticTypeId) {
						case "Null<Int>":
							"The final typed Haxe body sends one exact Null<Int>/Obj.t value through the compiler-owned Haxe exception channel without another box. The runtime tag comes from the carried value, so non-null matches Int while null remains Dynamic-only.";
						case "Null<Bool>":
							"The final typed Haxe body sends one exact Null<Bool>/Obj.t value through the compiler-owned Haxe exception channel. Null remains the existing sentinel; a non-null carrier is normalized once into the unambiguous boxed-Bool exception representation so it matches Bool rather than Int.";
						case "Dynamic":
							"The final typed Haxe body sends one Dynamic/Obj.t value through the compiler-owned Haxe exception channel without reboxing or changing the payload. Dynamic is the only static tag; the runtime derives any more specific primitive or class tag from the carried value, while null remains Dynamic-only.";
						case "haxe.Exception", "haxe.ValueException":
							'The final typed Haxe body sends one exact ${representation.semanticTypeId}/${representation.carrierTypeId} generated wrapper through the compiler-owned Haxe exception channel. Obj.t is only the in-flight carrier; the original wrapper object is preserved, and its existing runtime class marker derives the applicable haxe.Exception and haxe.ValueException tags without syntax-time hierarchy reconstruction.';
						case _ if (enumRepresentation):
							'The final typed Haxe body throws one directly visible ${representation.semanticTypeId} constructor carried as its native OCaml variant. The compiler records the enum name before syntax, evaluates the constructor once, and applies HxEnum.box_if_needed so exact enum and Dynamic catches receive the original constructor and payload.';
						case _ if (nominalRepresentation != null):
							'The final typed Haxe body sends one already-sealed ${representation.semanticTypeId}/${representation.carrierTypeId} nominal record through the compiler-owned Haxe exception channel. Obj.t is only the in-flight carrier; the existing runtime class marker derives the concrete tag for a non-null record, while null remains Dynamic-only.';
						case _ if (runtimeClassRepresentation):
							'The final typed Haxe body sends one generated ${representation.semanticTypeId} class value through the compiler-owned Haxe exception channel. Obj.t is only the in-flight carrier. The runtime reads the value\'s existing __hx_type marker and adds its concrete class and parent-class tags before any source catch recovers a typed variable.';
						case _:
							'The final typed Haxe body sends this exact ${representation.semanticTypeId}/${representation.carrierTypeId} value through the compiler-owned Haxe exception channel. The selected payload conversion preserves that represented value in the private Obj.t carrier. The sealed tag policy always admits Dynamic and derives the exact primitive tag from the carried runtime value, so a null String remains Dynamic rather than matching String.';
					};
					final decision:OcamlControlDecision = {
						id: controlId(OcamlControlTransferKind.Throw, path, OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID),
						source: throwSource,
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
							representationRevision: representation.representationRevision,
							arrayDescriptorId: representation.arrayDescriptorId,
							arrayDescriptorRevision: representation.arrayDescriptorRevision,
							arrayLiteralProducerId: representation.arrayLiteralProducerId,
							arrayLiteralProducerPlanRevision: representation.arrayLiteralProducerPlanRevision,
							conversion: conversion,
							nominalRepresentation: nominalRepresentation,
							proofId: proofId,
							proofClaim: proofClaim
						},
						runtimeTags: OcamlControlPlan.expectedThrowTags(representation.semanticTypeId, nominalRepresentation != null, enumRepresentation,
							representedArray, runtimeClassRepresentation),
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
					final trySource = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final catchOccurrenceIdentity = catchOccurrenceId(path);
					final tryBodyResultPolicy = catchBranchResultPolicy(expression.t, tryExpression);
					final clauseBodyResultPolicies = catches.map(entry -> catchBranchResultPolicy(expression.t, entry.expr));
					final catchBlockers:Array<OcamlControlAdmissionBlocker> = [];
					if (catches.length == 0) {
						catchBlockers.push(OcamlControlAdmissionContract.blocker("catch-chain-empty", catchOccurrenceIdentity, trySource));
					}
					for (index => entry in catches) {
						if (selectCatchType(entry.v.t) == null) {
							catchBlockers.push(OcamlControlAdmissionContract.blocker("catch-clause-unrepresented",
								catchOccurrenceIdentity + ":clause:" + index, OcamlLoweredOrigin.sourceSpan(entry.expr.pos),
								haxe.macro.TypeTools.toString(entry.v.t)));
						}
					}
					final catchTypesAdmitted = catchBlockers.length == 0;
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
							bodyResultPolicy: clauseBodyResultPolicies[index],
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
					var admittedChainId:Null<String> = null;
					if (admitted) {
						final chainId = catchChainId(path);
						admittedChainId = chainId;
						final proofClaim = 'The final typed Haxe body fixes all ${clauses.length} catch clauses in source order before target syntax. Compiler-owned Haxe exceptions and target-native exceptions enter the same ordered predicates, but unmatched values return through their original channel and compiler-private return/loop signals bypass every source catch.';
						final chain:OcamlCatchChainDecision = {
							id: chainId,
							source: trySource,
							clauses: clauses,
							tryBodyResultPolicy: tryBodyResultPolicy,
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
							reason: "This complete source catch chain has represented primitive, ordinary-enum, monomorphic-class, Haxe exception-wrapper, or Dynamic matching and payload binding fixed before OCaml syntax.",
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
						occurrenceId: catchOccurrenceIdentity,
						source: trySource,
						chainId: admittedChainId,
						tryBodyResultPolicy: tryBodyResultPolicy,
						clauseBodyResultPolicies: clauseBodyResultPolicies
					});
					catchAdmissions.push({
						occurrenceId: catchOccurrenceIdentity,
						source: trySource,
						status: admittedChainId == null ? OcamlControlAdmissionStatus.Blocked : OcamlControlAdmissionStatus.Admitted,
						chainId: admittedChainId,
						blockers: catchBlockers
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

		if (typedValueFallbackRequired) {
			if (typedBoundary == null || typedBoundary.resultKind != OcamlCallResultKind.Value)
				throw 'reflaxe.ocaml [ocaml-control:missing-typed-result]: function "${binding.functionId}" requested a typed return fallback without a value boundary';
			decisions = decisions.filter(decision -> decision.kind != OcamlControlTransferKind.Return);
			decisionOccurrences = decisionOccurrences.filter(occurrence -> {
				final decision = Lambda.find(decisions, candidate -> candidate.id == occurrence.decisionId);
				return decision != null;
			});
			returnBlockers.resize(0);
			returnFamilyAdmitted = true;
			for (observed in observedReturns) {
				final value = observed.value;
				final inputSemanticTypeId = observed.semanticTypeId;
				if (value == null || inputSemanticTypeId == null) {
					returnFamilyAdmitted = false;
					returnBlockers.push(OcamlControlAdmissionContract.blocker("return-payload-missing",
						controlBlockerOccurrenceId(OcamlControlTransferKind.Return, observed.path), observed.source));
					continue;
				}
				final payload = typedFunctionReturnPayload(inputSemanticTypeId, typedBoundary);
				final decision:OcamlControlDecision = {
					id: controlId(OcamlControlTransferKind.Return, observed.path, binding.functionId),
					source: observed.source,
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
					reason: "This nested return uses the result type already checked for its exact Haxe function. The private signal erases the value only until the matching function handler recovers it.",
					proofId: OcamlControlPlan.TYPED_FUNCTION_RESULT_RETURN_PROOF_ID,
					proofClaim: typedBoundary.proofClaim,
					functionId: binding.functionId,
					programRevision: binding.programRevision,
					bodyRevision: binding.bodyRevision,
					pipelineRevision: binding.pipelineRevision
				};
				decisions.push(decision);
				decisionOccurrences.push({
					expression: observed.expression,
					decisionId: decision.id
				});
			}
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
		final admission = OcamlControlAdmissionContract.create(binding, [
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Return, returnOccurrenceCount,
				Lambda.count(decisions, decision -> decision.kind == OcamlControlTransferKind.Return), returnFamilyAdmitted, returnBlockers),
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Loop, loopOccurrenceCount,
				Lambda.count(decisions, decision -> decision.kind == OcamlControlTransferKind.Break
					|| decision.kind == OcamlControlTransferKind.Continue),
				loopFamilyAdmitted, loopBlockers),
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Throw, throwOccurrenceCount,
				Lambda.count(decisions, decision -> decision.kind == OcamlControlTransferKind.Throw), throwFamilyAdmitted, throwBlockers)
		], catchAdmissions);
		return new OcamlControlPlan(returnFamilyAdmitted, loopFamilyAdmitted, throwFamilyAdmitted, binding, targets, decisions, targetOccurrences,
			decisionOccurrences, catchChains, catchOccurrences, admission, statementResultOccurrences);
	}

	static function catchBranchResultPolicy(tryResultType:Type, branch:TypedExpr):OcamlCatchBranchResultPolicy {
		return isVoid(tryResultType)
			&& !OcamlControlFlowFacts.definitelyReturnsOrThrows(branch) ? OcamlCatchBranchResultPolicy.DiscardCompletedValueToUnit : OcamlCatchBranchResultPolicy.PreserveTypedResult;
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
		if (OcamlRepresentationRegistry.isExactFloat(type)) {
			final representation = representations.selectExactFloat(OcamlRepresentationDomain.InternalValue);
			return {
				semanticTypeId: "Float",
				outputCarrierTypeId: representation.carrierTypeId,
				outputRepresentationId: representation.id,
				matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
				runtimeTag: "Float",
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
		final runtimeClassIdentity = OcamlControlPlan.runtimeClassCarrierIdentityForType(type);
		if (runtimeClassIdentity != null) {
			return {
				semanticTypeId: runtimeClassIdentity.semanticTypeId,
				outputCarrierTypeId: runtimeClassIdentity.carrierTypeId,
				outputRepresentationId: runtimeClassIdentity.catchRepresentationId,
				matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
				runtimeTag: runtimeClassIdentity.semanticTypeId,
				conversion: OcamlCatchPayloadConversion.RecoverRuntimeClassValue,
				nominalRepresentation: null
			};
		}
		final enumIdentity = OcamlEnumDynamicCarrier.fromType(type);
		if (enumIdentity != null) {
			return {
				semanticTypeId: enumIdentity.semanticTypeId,
				outputCarrierTypeId: enumIdentity.carrierTypeId,
				outputRepresentationId: OcamlControlPlan.enumCatchRepresentationId(enumIdentity.semanticTypeId),
				matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
				runtimeTag: enumIdentity.semanticTypeId,
				conversion: OcamlCatchPayloadConversion.RecoverEnumValue,
				nominalRepresentation: null
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
				final reference = localRepresentations.referenceFor(localIdentities.requireHostId(local.id).id);
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

	/** Selects a value representation that may cross one private return signal. */
	function returnRepresentation(expression:TypedExpr, boundary:Null<OcamlFunctionResultBoundaryPlan>):Null<OcamlRepresentationDecision> {
		final exact = exactValueRepresentation(expression);
		if (exact != null)
			return exact;
		if (OcamlRepresentationRegistry.isExactDynamic(expression.t))
			return representations.selectExactDynamic(OcamlRepresentationDomain.InternalValue);
		final enumProof = boundary == null ? null : boundary.nullableEnum;
		final unwrapped = unwrapTransparent(expression);
		final isNull = switch (unwrapped.expr) {
			case TConst(TNull): true;
			case _: false;
		};
		if (isNull && enumProof != null && unwrapped.t != null) {
			final nullRepresentation = representations.require('representation:${enumProof.nullableSemanticTypeId}:internal-value', binding.programRevision);
			if (nullRepresentation.semanticTypeId == enumProof.nullableSemanticTypeId
				&& nullRepresentation.carrierTypeId == "Obj.t"
				&& nullRepresentation.domain == OcamlRepresentationDomain.InternalValue) {
				return nullRepresentation;
			}
		}
		final enumIdentity = OcamlControlPlan.exactEnumReturnIdentity(expression);
		if (enumIdentity != null && enumProof != null && enumIdentity.semanticTypeId == enumProof.semanticTypeId) {
			final enumRepresentation = representations.require('representation:${enumIdentity.semanticTypeId}:internal-value', binding.programRevision);
			return enumRepresentation.carrierTypeId == enumIdentity.carrierTypeId ? enumRepresentation : null;
		}
		final proof = boundary == null ? null : boundary.anonymousStructure;
		if (!isNull || proof == null || OcamlAnonymousStructurePlan.semanticTypeIdForType(unwrapped.t) != proof.semanticTypeId)
			return null;
		final representation = representations.require(proof.representationId, binding.programRevision);
		return representation.revision == proof.representationRevision
			&& representation.semanticTypeId == proof.semanticTypeId
			&& representation.carrierTypeId == "Obj.t"
			&& representation.domain == OcamlRepresentationDomain.InternalValue
			&& representation.boxingPolicy == OcamlRepresentationBoxingPolicy.DirectRuntimeContainer ? representation : null;
	}

	/**
		Selects an already represented local or direct literal for a throw.

		A local must already be sealed by the local-representation planner. A direct
		literal must already have a producer decision that fixes its result carrier,
		descriptor, and exactly-once element schedule. This prevents control from
		choosing array construction, element types, fields, call results, generic
		arrays, or mutable/captured storage carriers. General represented-array
		admission remains `Array<Int>`-only. A direct literal may additionally use the
		proved String producer, whose descriptor and representation were selected
		before control planning.
	**/
	function representedArrayThrowRepresentation(expression:TypedExpr):Null<OcamlRepresentedArrayThrowSelection> {
		final unwrapped = unwrapTransparent(expression);
		return switch (unwrapped.expr) {
			case TLocal(local):
				final normalized = OcamlRepresentationRegistry.normalizedDirectFlatArray(unwrapped.t);
				if (normalized == null) {
					null;
				} else {
					final reference = localRepresentations.referenceFor(localIdentities.requireHostId(local.id).id);
					if (reference == null
						|| reference.semanticTypeId != normalized.arraySemanticTypeId
						|| reference.domain != OcamlRepresentationDomain.InternalValue
						|| !StringTools.startsWith(reference.representationRevision, "sha256:")) {
						null;
					} else {
						final representation = representations.require(reference.representationId, binding.programRevision);
						if (representation.revision != reference.representationRevision
							|| representation.semanticTypeId != normalized.arraySemanticTypeId
							|| representation.domain != OcamlRepresentationDomain.InternalValue
							|| representation.arrayDescriptorId == null
							|| representation.arrayDescriptorRevision == null) {
							null;
						} else {
							final descriptor = representations.requireRepresentedArray(representation.arrayDescriptorId,
								representation.arrayDescriptorRevision, binding.programRevision);
							descriptor.arraySemanticTypeId == normalized.arraySemanticTypeId
							&& descriptor.elementSemanticTypeId == normalized.elementSemanticTypeId && descriptor.arrayCarrierTypeId == representation.carrierTypeId ? {
								representation: representation,
								arrayLiteralProducerId: null,
								arrayLiteralProducerPlanRevision: null
							} : null;
						}
					}
				}
			case TArrayDecl(_):
				final normalized = OcamlDirectArraySourceIdentity.normalize(unwrapped.t);
				if (normalized == null) {
					null;
				} else {
					final producer = arrayLiteralProducers.decisionFor(unwrapped);
					if (producer == null) {
						null;
					} else {
						final sealed = arrayLiteralProducers.requireFor(unwrapped, representations);
						if (sealed.functionId != binding.functionId
							|| sealed.programRevision != binding.programRevision
							|| sealed.bodyRevision != binding.bodyRevision
							|| sealed.pipelineRevision != binding.pipelineRevision
							|| sealed.arraySemanticTypeId != normalized.arraySemanticTypeId
							|| sealed.elementSemanticTypeId != normalized.elementSemanticTypeId) {
							null;
						} else {
							final representation = representations.require(sealed.resultRepresentationId, binding.programRevision);
							representation.revision != sealed.resultRepresentationRevision ? null : {
								representation: representation,
								arrayLiteralProducerId: sealed.id,
								arrayLiteralProducerPlanRevision: arrayLiteralProducers.revision
							};
						}
					}
				}
			case _:
				null;
		}
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
		An exact immutable `Array<Int>` local may also cross opaquely once its
		program representation is already sealed; this preserves the existing
		mutable array object without introducing an array-valued call boundary.
		Other control families remain on their narrower proofs.
	**/
	function throwRepresentation(expression:TypedExpr):Null<OcamlControlThrowRepresentation> {
		final haxeExceptionTypeId = OcamlControlPlan.haxeExceptionWrapperTypeId(expression.t);
		if (haxeExceptionTypeId != null) {
			return haxeExceptionTypeId == "haxe.Exception" ? {
				semanticTypeId: haxeExceptionTypeId,
				carrierTypeId: "Haxe_Exception.t",
				representationId: OcamlControlPlan.HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID,
				representationRevision: null,
				arrayDescriptorId: null,
				arrayDescriptorRevision: null,
				arrayLiteralProducerId: null,
				arrayLiteralProducerPlanRevision: null,
				nominalRepresentation: null,
				enumIdentity: null,
				runtimeClassIdentity: null
			} : {
				semanticTypeId: haxeExceptionTypeId,
				carrierTypeId: "Haxe_ValueException.t",
				representationId: OcamlControlPlan.HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID,
				representationRevision: null,
				arrayDescriptorId: null,
				arrayDescriptorRevision: null,
				arrayLiteralProducerId: null,
				arrayLiteralProducerPlanRevision: null,
				nominalRepresentation: null,
				enumIdentity: null,
				runtimeClassIdentity: null
				};
		}
		final exact = exactValueRepresentation(expression);
		if (exact != null) {
			return {
				semanticTypeId: exact.semanticTypeId,
				carrierTypeId: exact.carrierTypeId,
				representationId: exact.id,
				representationRevision: exact.revision,
				arrayDescriptorId: exact.arrayDescriptorId,
				arrayDescriptorRevision: exact.arrayDescriptorRevision,
				arrayLiteralProducerId: null,
				arrayLiteralProducerPlanRevision: null,
				nominalRepresentation: nominalProofFor(exact),
				enumIdentity: null,
				runtimeClassIdentity: null
			};
		}
		final representedArray = representedArrayThrowRepresentation(expression);
		if (representedArray != null) {
			return {
				semanticTypeId: representedArray.representation.semanticTypeId,
				carrierTypeId: representedArray.representation.carrierTypeId,
				representationId: representedArray.representation.id,
				representationRevision: representedArray.representation.revision,
				arrayDescriptorId: representedArray.representation.arrayDescriptorId,
				arrayDescriptorRevision: representedArray.representation.arrayDescriptorRevision,
				arrayLiteralProducerId: representedArray.arrayLiteralProducerId,
				arrayLiteralProducerPlanRevision: representedArray.arrayLiteralProducerPlanRevision,
				nominalRepresentation: null,
				enumIdentity: null,
				runtimeClassIdentity: null
			};
		}
		switch (haxe.macro.TypeTools.follow(expression.t)) {
			case TDynamic(_):
				return {
					semanticTypeId: "Dynamic",
					carrierTypeId: "Obj.t",
					representationId: OcamlControlPlan.DYNAMIC_CONTROL_REPRESENTATION_ID,
					representationRevision: null,
					arrayDescriptorId: null,
					arrayDescriptorRevision: null,
					arrayLiteralProducerId: null,
					arrayLiteralProducerPlanRevision: null,
					nominalRepresentation: null,
					enumIdentity: null,
					runtimeClassIdentity: null
				};
			case _:
		}
		final enumIdentity = OcamlEnumDynamicCarrier.fromDirectValue(expression);
		if (enumIdentity != null) {
			return {
				semanticTypeId: enumIdentity.semanticTypeId,
				carrierTypeId: enumIdentity.carrierTypeId,
				representationId: OcamlControlPlan.enumThrowRepresentationId(enumIdentity.semanticTypeId),
				representationRevision: null,
				arrayDescriptorId: null,
				arrayDescriptorRevision: null,
				arrayLiteralProducerId: null,
				arrayLiteralProducerPlanRevision: null,
				nominalRepresentation: null,
				enumIdentity: enumIdentity,
				runtimeClassIdentity: null
			};
		}
		final nominalClass = representations.monomorphicClassForType(expression.t);
		if (nominalClass != null) {
			final representation = representations.monomorphicClassValue(nominalClass.semanticTypeId);
			if (representation != null) {
				return {
					semanticTypeId: representation.semanticTypeId,
					carrierTypeId: representation.carrierTypeId,
					representationId: representation.id,
					representationRevision: representation.revision,
					arrayDescriptorId: representation.arrayDescriptorId,
					arrayDescriptorRevision: representation.arrayDescriptorRevision,
					arrayLiteralProducerId: null,
					arrayLiteralProducerPlanRevision: null,
					nominalRepresentation: nominalProofFor(representation),
					enumIdentity: null,
					runtimeClassIdentity: null
				};
			}
		}
		final runtimeClassIdentity = OcamlControlPlan.runtimeClassCarrierIdentityForType(expression.t);
		return runtimeClassIdentity == null ? null : {
			semanticTypeId: runtimeClassIdentity.semanticTypeId,
			carrierTypeId: runtimeClassIdentity.carrierTypeId,
			representationId: runtimeClassIdentity.throwRepresentationId,
			representationRevision: null,
			arrayDescriptorId: null,
			arrayDescriptorRevision: null,
			arrayLiteralProducerId: null,
			arrayLiteralProducerPlanRevision: null,
			nominalRepresentation: null,
			enumIdentity: null,
			runtimeClassIdentity: runtimeClassIdentity
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
		if (sameSide
			&& (OcamlControlPlan.isAdmittedNullableSide(input.semanticTypeId, input.carrierTypeId, input.id)
				|| OcamlControlPlan.isExactNullableEnumSide(input.semanticTypeId, input.carrierTypeId, input.id))) {
			final proofClaim = 'The final typed Haxe body assigns this return to the current ${input.semanticTypeId} function. The selected private runtime signal already carries the exact ${input.carrierTypeId} nullable value, so syntax must preserve that carrier without another box, unchecked cast, or boundary recovery.';
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.PreserveNullableCarrier, OcamlControlPlan.NULLABLE_CARRIER_RETURN_PROOF_ID,
				proofClaim);
		}
		if (sameSide
			&& OcamlControlPlan.isAdmittedAnonymousSide(input.semanticTypeId, input.carrierTypeId, input.id)
			&& input.boxingPolicy == OcamlRepresentationBoxingPolicy.DirectRuntimeContainer) {
			final proofClaim = 'The final typed null return belongs to the same ${input.semanticTypeId} shape as the function\'s direct object-literal result. The anonymous-structure planner already selected this exact Obj.t runtime-container representation, so the private return signal preserves the runtime null sentinel and the function boundary recovers the same carrier without boxing, casting, or shape inference.';
			return {
				inputSemanticTypeId: input.semanticTypeId,
				inputCarrierTypeId: input.carrierTypeId,
				inputRepresentationId: input.id,
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: output.outputSemanticTypeId,
				outputCarrierTypeId: output.outputCarrierTypeId,
				outputRepresentationId: output.outputRepresentationId,
				representationRevision: input.revision,
				conversion: OcamlControlPayloadConversion.PreserveAnonymousCarrier,
				nominalRepresentation: null,
				proofId: OcamlControlPlan.ANONYMOUS_CARRIER_RETURN_PROOF_ID,
				proofClaim: proofClaim
			};
		}
		if (sameSide
			&& input.semanticTypeId == "Dynamic"
			&& input.carrierTypeId == "Obj.t"
			&& input.id == "representation:Dynamic:internal-value") {
			final proofClaim = "The final typed Haxe body already stores this Dynamic return as the selected Obj.t carrier. The private return signal and the callable boundary preserve that same carrier without another box, unchecked cast, or runtime type guess.";
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.PreserveDynamicReturnCarrier, OcamlControlPlan.DYNAMIC_RETURN_PROOF_ID,
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
		if (input.carrierTypeId == '${OcamlEnumDynamicCarrier.CARRIER_MODEL}:${input.semanticTypeId}'
			&& output.outputSemanticTypeId == 'Null<${input.semanticTypeId}>'
			&& output.outputCarrierTypeId == "Obj.t") {
			final proofClaim = "The final typed Haxe body converts this exact enum return to the function's exact Null<Enum> Obj.t carrier once before the private return signal. The owning function boundary preserves that carrier unchanged.";
			return makeReturnPayload(input, output, OcamlControlPayloadConversion.BoxExactEnumToNullableCarrier,
				OcamlControlPlan.NULLABLE_ENUM_CONVERSION_RETURN_PROOF_ID, proofClaim);
		}
		return null;
	}

	/** Builds one function-local fallback from Haxe's checked return assignment. */
	static function typedFunctionReturnPayload(inputSemanticTypeId:String, boundary:OcamlTypedFunctionResultBoundaryPlan):OcamlControlPayloadPlan {
		return {
			inputSemanticTypeId: inputSemanticTypeId,
			inputCarrierTypeId: OcamlTypedFunctionResultBoundary.INFERRED_CARRIER_TYPE_ID,
			inputRepresentationId: OcamlTypedFunctionResultBoundary.representationId(boundary.functionId, "input", inputSemanticTypeId),
			signalCarrierTypeId: "Obj.t",
			outputSemanticTypeId: boundary.semanticTypeId,
			outputCarrierTypeId: OcamlTypedFunctionResultBoundary.INFERRED_CARRIER_TYPE_ID,
			outputRepresentationId: OcamlTypedFunctionResultBoundary.representationId(boundary.functionId, "output", boundary.semanticTypeId),
			conversion: inputSemanticTypeId == "Bool"
			&& boundary.semanticTypeId == "Dynamic" ? OcamlControlPayloadConversion.BoxBoolAndRecoverDynamicTypedFunctionResult : OcamlControlPayloadConversion.BoxAndRecoverTypedFunctionResult,
			nominalRepresentation: null,
			proofId: OcamlControlPlan.TYPED_FUNCTION_RESULT_RETURN_PROOF_ID,
			proofClaim: boundary.proofClaim
		};
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
			case PreserveAnonymousCarrier:
				"This typed null return is nested below the function's direct object-literal result, so it preserves that exact anonymous runtime-container carrier through one revision-bound private signal.";
			case PreserveDynamicReturnCarrier:
				"This return is nested below the function's direct result path, so it preserves the existing Dynamic Obj.t carrier through one revision-bound private runtime signal.";
			case BoxExactIntToNullableCarrier, BoxExactBoolToNullableCarrier, BoxExactEnumToNullableCarrier:
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

	function controlBlockerOccurrenceId(kind:OcamlControlTransferKind, path:String):String {
		return "control-admission-occurrence:"
			+ (kind : String)
			+ ":"
			+ Sha256.encode(binding.functionId + "|" + (kind : String) + "|" + path).substr(0, 24);
	}

	function catchChainId(path:String):String {
		return "control-catch-chain:" + Sha256.encode(binding.functionId + "|" + path).substr(0, 24);
	}

	function statementResultOccurrenceId(path:String):String {
		return "control-statement-result:" + Sha256.encode(binding.functionId + "|" + path).substr(0, 24);
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

	function admittedBoundaryPayload(boundary:Null<OcamlFunctionResultBoundaryPlan>):Null<OcamlCallValuePlan> {
		if (boundary == null || boundary.resultKind != OcamlCallResultKind.Value || boundary.result == null) {
			return null;
		}
		OcamlFunctionResultBoundary.require(boundary);
		final result = boundary.result;
		final anonymous = boundary.anonymousStructure;
		final anonymousIdentity = anonymous != null
			&& result.inputSemanticTypeId == anonymous.semanticTypeId
			&& result.inputCarrierTypeId == "Obj.t"
			&& result.inputRepresentationId == anonymous.representationId
			&& result.outputSemanticTypeId == anonymous.semanticTypeId
			&& result.outputCarrierTypeId == "Obj.t"
			&& result.outputRepresentationId == anonymous.representationId
			&& result.conversion == OcamlCallCarrierConversion.Identity;
		if (anonymousIdentity)
			return OcamlCallPlan.copyValue(result);
		final exactIdentity = result.inputSemanticTypeId == result.outputSemanticTypeId
			&& result.inputCarrierTypeId == result.outputCarrierTypeId
			&& result.inputRepresentationId == result.outputRepresentationId
			&& result.conversion == OcamlCallCarrierConversion.Identity
			&& OcamlControlPlan.isAdmittedExactSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId);
		if (exactIdentity)
			return OcamlCallPlan.copyValue(result);
		final dynamicIdentity = result.inputSemanticTypeId == "Dynamic"
			&& result.inputCarrierTypeId == "Obj.t"
			&& result.inputRepresentationId == "representation:Dynamic:internal-value"
			&& result.outputSemanticTypeId == "Dynamic"
			&& result.outputCarrierTypeId == "Obj.t"
			&& result.outputRepresentationId == "representation:Dynamic:internal-value"
			&& result.conversion == OcamlCallCarrierConversion.Identity;
		if (dynamicIdentity)
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
		final checkedNullableIntResult = result.inputSemanticTypeId == "Null<Int>"
			&& result.inputCarrierTypeId == "Obj.t"
			&& result.inputRepresentationId == "representation:Null<Int>:internal-value"
			&& result.outputSemanticTypeId == "Int"
			&& result.outputCarrierTypeId == "int"
			&& result.outputRepresentationId == "representation:Int:internal-value"
			&& result.conversion == OcamlCallCarrierConversion.CheckedUnboxNullableInt;
		if (checkedNullableIntResult) {
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
		final nullableOutput = OcamlControlPlan.isAdmittedNullableSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId)
			|| (result.inputSemanticTypeId.length > 0
				&& result.outputSemanticTypeId == 'Null<${result.inputSemanticTypeId}>'
				&& result.outputCarrierTypeId == "Obj.t"
				&& result.outputRepresentationId == 'representation:${result.outputSemanticTypeId}:internal-value');
		final validDirectConversion = (result.inputSemanticTypeId == "Int"
			&& result.outputSemanticTypeId == "Null<Int>"
			&& result.conversion == OcamlCallCarrierConversion.BoxExactIntToNullableInt)
			|| (result.inputSemanticTypeId == "Bool"
				&& result.outputSemanticTypeId == "Null<Bool>"
				&& result.conversion == OcamlCallCarrierConversion.BoxExactBoolToNullableBool)
			|| (result.inputSemanticTypeId.length > 0
				&& result.inputCarrierTypeId == '${OcamlEnumDynamicCarrier.CARRIER_MODEL}:${result.inputSemanticTypeId}'
				&& result.outputSemanticTypeId == 'Null<${result.inputSemanticTypeId}>'
				&& result.outputCarrierTypeId == "Obj.t"
				&& result.conversion == OcamlCallCarrierConversion.BoxExactEnumToNullableEnum)
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

	static function admittedEffectOnlyVoidBoundary(boundary:Null<OcamlFunctionResultBoundaryPlan>):Bool {
		return boundary != null && boundary.resultKind == OcamlCallResultKind.EffectOnlyVoid && boundary.result == null;
	}
}
#end
