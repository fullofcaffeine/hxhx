package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
import haxe.macro.Type.TVar;
import haxe.macro.Type.TypedExpr;
import reflaxe.data.ClassFuncData;
import reflaxe.lifecycle.FunctionBodyRevision;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableDeclarationPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan.OcamlArrayLiteralProducerPlanner;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementDecision;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementPlanner;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan.OcamlBytesAccessPlanner;
import reflaxe.ocaml.lowered.OcamlBytesMutationPlan;
import reflaxe.ocaml.lowered.OcamlBytesMutationPlan.OcamlBytesMutationPlanner;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan.OcamlBytesProducerPlanner;
import reflaxe.ocaml.lowered.OcamlBytesReadPlan;
import reflaxe.ocaml.lowered.OcamlBytesReadPlan.OcamlBytesReadPlanner;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan;
import reflaxe.ocaml.lowered.OcamlAnonymousStructurePlan.OcamlAnonymousStructurePlanner;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldPlanner;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionSnapshot;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary.OcamlFunctionResultBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceCallDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationRecord;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDecision;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectComparePlanner;

/** One validated target plan that is immutable after its function is sealed. */
typedef OcamlSealedPlacePlan = {
	final originId:String;
	final nodeKind:String;
	final fingerprint:String;
	final binding:OcamlFunctionPlanBinding;
	final operation:OcamlLoweredPlaceOperation;
}

/**
	All request-local target decisions sealed for one exact final function body.

	Some plans keep exact typed-expression keys so syntax can consume the
	decision chosen for that request without reconstructing an occurrence from
	source positions. Callers must not retain this object across requests.
**/
typedef OcamlSealedFunctionPlan = {
	final binding:OcamlFunctionPlanBinding;
	final localStorage:OcamlLocalStoragePlan;
	final localRepresentations:OcamlLocalRepresentationPlan;
	final containerElements:OcamlContainerElementPlan;
	final arrayLiteralProducers:OcamlArrayLiteralProducerPlan;
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final structuralFields:OcamlStructuralFieldPlan;
	final bytesAccesses:OcamlBytesAccessPlan;
	final bytesMutations:OcamlBytesMutationPlan;
	final bytesProducers:OcamlBytesProducerPlan;
	final bytesReads:OcamlBytesReadPlan;
	final imapInterfaces:OcamlIMapInterfacePlan;
	final calls:OcamlCallPlan;
	final reflectCompare:OcamlReflectComparePlan;
	final controls:OcamlControlPlan;
	final callableBoundary:Null<OcamlCallableBoundaryPlan>;
	final functionResultBoundary:Null<OcamlFunctionResultBoundaryPlan>;
	final constructionBoundary:Null<OcamlCallableBoundaryPlan>;
}

/**
	One exact, request-local handoff from sealed planning to target syntax.

	Creating this input freshly observes the final typed body once. Syntax must
	consume the plan, host-local identities, and optional constructor boundary
	together instead of requesting each through another body observation. The
	input is request-local and must never be cached across compiler requests.
**/
typedef OcamlFunctionSyntaxInput = {
	final plan:OcamlSealedFunctionPlan;
	final localIdentities:LexicalLocalIdentityPlan;
	final constructionBoundary:Null<OcamlCallableBoundaryPlan>;
}

/**
	The represented result and control facts sealed for one nested function literal.

	This is request-local because `controls` keeps exact typed-expression keys for
	the active compiler request. The copied decisions can appear in reports, but
	the plan object itself must be discarded when `beginProgram` starts the next
	request. `arrayLiteralProducers` is required even when it is empty. Therefore,
	target syntax can treat a missing literal decision as an error instead of
	quietly rebuilding the literal through the older generic array path.
**/
typedef OcamlSealedNestedFunctionPlan = {
	final occurrenceId:String;
	final parentBinding:OcamlFunctionPlanBinding;
	final binding:OcamlFunctionPlanBinding;
	final callableBoundary:OcamlCallableBoundaryPlan;
	final ?functionResultBoundary:OcamlFunctionResultBoundaryPlan;
	final controls:OcamlControlPlan;
	final arrayLiteralProducers:OcamlArrayLiteralProducerPlan;
	final imapInterfaces:OcamlIMapInterfacePlan;
}

/**
	Names one nested function even when its result behavior is not represented yet.

	The occurrence identifies the literal's stable place in the root typed body.
	The binding combines that occurrence with its immediate parent. Planning keeps
	this identity for every literal so a deeper child cannot be mistaken for a
	child of the ordinary root when the intermediate function is deferred.
**/
typedef OcamlNestedFunctionIdentity = {
	final occurrenceId:String;
	final parentBinding:OcamlFunctionPlanBinding;
	final binding:OcamlFunctionPlanBinding;
}

/**
	Gives syntax the nested function's identity and optional represented behavior.

	`plan == null` means that planning explicitly kept the older result or control
	path for this function. The binding still becomes the parent while syntax builds
	the function body, so any deeper function keeps the correct lexical owner.
**/
typedef OcamlNestedFunctionSyntaxDisposition = {
	final binding:OcamlFunctionPlanBinding;
	final imapInterfaces:OcamlIMapInterfacePlan;
	final plan:Null<OcamlSealedNestedFunctionPlan>;
}

/**
	All target-owned decisions sealed for one exact non-function expression root.

	`binding.functionId` contains a stable root identity even though the shared
	binding schema predates standalone roots. This keeps the producer contract
	revision-bound without pretending that a field initializer is a function.
**/
typedef OcamlSealedStandaloneExpressionPlan = {
	final binding:OcamlFunctionPlanBinding;
	final containerElements:OcamlContainerElementPlan;
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final structuralFields:OcamlStructuralFieldPlan;
	final bytesAccesses:OcamlBytesAccessPlan;
	final bytesMutations:OcamlBytesMutationPlan;
	final bytesProducers:OcamlBytesProducerPlan;
	final bytesReads:OcamlBytesReadPlan;
	final reflectCompare:OcamlReflectComparePlan;
}

private typedef OcamlSealedFunctionRecord = {
	final plan:OcamlSealedFunctionPlan;

	/**
		Request-local adapter from the active host's `TVar.id` values to the stable
		identities retained by `plan`.
	**/
	final localIdentities:LexicalLocalIdentityPlan;

	final originIds:Array<String>;
}

/**
	One nested literal observed while sealing its parent function.

	`plan == null` is an explicit deferral, not a missing plan. Keeping that
	distinction lets syntax use the legacy path only for a literal the planner
	actually saw and deliberately left outside the represented nested-result slice.
**/
private typedef OcamlNestedFunctionRecord = {
	final binding:OcamlFunctionPlanBinding;
	final parentBinding:OcamlFunctionPlanBinding;
	final bodyExternalLocals:Array<TVar>;
	final observedBodyRevision:String;
	final occurrenceId:String;
	final imapInterfaces:OcamlIMapInterfacePlan;
	final plan:Null<OcamlSealedNestedFunctionPlan>;
	final deferredReason:Null<String>;
}

/**
	The exact ordinary-function binding and structural lookup that own its literals.

	The binding includes the root body's revision. Keeping it beside the lookup
	prevents a later caller from reusing real occurrence identities after the root
	body changed, even when the program and function names stayed the same.
**/
private typedef OcamlRootIdentityRecord = {
	final binding:OcamlFunctionPlanBinding;
	final identities:LexicalLocalIdentityPlan;
}

/**
	Owns revision-bound lowered plans between final typed preprocessing and syntax.

	A new compilation request clears the registry. Each function is planned and
	validated once, then its place operations, local-storage choices, and
	occurrence-bound carrier conversions are sealed against the exact body
	revision. A mismatch is an internal compiler error, never a request to
	reconstruct source semantics during emission.
**/
class OcamlFunctionPlanRegistry {
	public static inline final PIPELINE_REVISION = "ocaml-function-plans-v82";
	public static inline final NESTED_FUNCTION_PIPELINE_REVISION = "ocaml-nested-function-plans-v15";
	public static inline final STANDALONE_PIPELINE_REVISION = "ocaml-standalone-expression-plans-v3";

	/**
		Builds the only nested-function ID accepted for one parent and occurrence.

		An occurrence ID names the literal's structural position. Combining it with
		the immediate parent keeps deeply nested functions in the correct lexical
		chain. The registry recomputes this value during sealing so a valid identity
		from another literal cannot be paired with a plausible-looking function ID.
	**/
	public static function nestedFunctionId(parentFunctionId:String, occurrenceId:String):String {
		if (parentFunctionId.length == 0 || !LexicalLocalIdentityPlan.isReusableFunctionOccurrenceId(occurrenceId))
			throw "reflaxe.ocaml [ocaml-nested-function:missing-identity]: a nested function ID requires one parent and one stable occurrence";
		return parentFunctionId + "|nested-function|" + haxe.crypto.Sha256.encode(parentFunctionId + "|" + occurrenceId).substr(0, 24);
	}

	var currentProgramRevision:Null<String> = null;
	final plansByOrigin:StringMap<OcamlSealedPlacePlan> = new StringMap();
	final originsByFunction:StringMap<Array<String>> = new StringMap();
	final sealedFunctions:StringMap<OcamlSealedFunctionRecord> = new StringMap();
	final nestedFunctionsByExpression:ObjectMap<TypedExpr, OcamlNestedFunctionRecord> = new ObjectMap();
	final nestedFunctionsByOccurrence:StringMap<OcamlSealedNestedFunctionPlan> = new StringMap();
	final nestedFunctionBindingsByOccurrence:StringMap<OcamlFunctionPlanBinding> = new StringMap();
	final nestedFunctionsByFunctionId:StringMap<OcamlNestedFunctionRecord> = new StringMap();
	final rootIdentityRecordsByFunctionId:StringMap<OcamlRootIdentityRecord> = new StringMap();
	// A nested function ID contains its parent text, but that text alone cannot
	// prove which ordinary function ultimately owns it. Keep the exact root owner
	// chosen during sealing so a deeper literal cannot cross into another root.
	final nestedFunctionRootOwnerById:StringMap<String> = new StringMap();
	final declaredCallableByCallee:StringMap<OcamlCallableDeclarationPlan> = new StringMap();
	final callableByCallee:StringMap<OcamlCallableBoundaryPlan> = new StringMap();
	final originByProtection:StringMap<String> = new StringMap();
	final standaloneContainerElementsById:StringMap<OcamlContainerElementDecision> = new StringMap();
	final standaloneRequiredContainerElementIds:StringMap<Bool> = new StringMap();
	final standaloneAnonymousStructuresById:StringMap<OcamlAnonymousStructureDecision> = new StringMap();
	final standaloneAnonymousOperationsById:StringMap<OcamlAnonymousStructureOperationDecision> = new StringMap();
	final standaloneStructuralFieldsById:StringMap<OcamlStructuralFieldDecision> = new StringMap();
	final standaloneReflectCompareById:StringMap<OcamlReflectCompareDecision> = new StringMap();

	public function new() {}

	/** Starts one request and discards every prior function plan. */
	public function beginProgram(programRevision:String):Void {
		if (programRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-lowering:missing-program-revision]: the target-selected program revision is empty";
		currentProgramRevision = programRevision;
		plansByOrigin.clear();
		originsByFunction.clear();
		sealedFunctions.clear();
		nestedFunctionsByExpression.clear();
		nestedFunctionsByOccurrence.clear();
		nestedFunctionBindingsByOccurrence.clear();
		nestedFunctionsByFunctionId.clear();
		rootIdentityRecordsByFunctionId.clear();
		nestedFunctionRootOwnerById.clear();
		declaredCallableByCallee.clear();
		callableByCallee.clear();
		originByProtection.clear();
		standaloneContainerElementsById.clear();
		standaloneRequiredContainerElementIds.clear();
		standaloneAnonymousStructuresById.clear();
		standaloneAnonymousOperationsById.clear();
		standaloneStructuralFieldsById.clear();
		standaloneReflectCompareById.clear();
	}

	/**
		Registers the one whole-body lexical lookup allowed for an ordinary function.

		The lookup maps request-local typed nodes to stable structural identities. Its
		owner text is not enough to prove that it was built from the complete function
		body, so nested planning must retain and reuse this exact lookup object for the
		current request.
	**/
	public function registerRootIdentityPlan(binding:OcamlFunctionPlanBinding, localIdentities:LexicalLocalIdentityPlan):Void {
		if (binding.programRevision != currentProgramRevision || binding.pipelineRevision != PIPELINE_REVISION)
			throw 'reflaxe.ocaml [ocaml-nested-function:stale-root-identities]: root function "${binding.functionId}" does not belong to the current ordinary-function pipeline';
		if (localIdentities.ownerId != binding.functionId)
			throw 'reflaxe.ocaml [ocaml-nested-function:foreign-root-identities]: root function "${binding.functionId}" received identities owned by "${localIdentities.ownerId}"';
		final current = rootIdentityRecordsByFunctionId.get(binding.functionId);
		if (current != null) {
			if (!sameBinding(current.binding, binding))
				throw 'reflaxe.ocaml [ocaml-nested-function:conflicting-root-binding]: root function "${binding.functionId}" changed binding after its whole-body identity lookup was registered';
			if (current.identities != localIdentities)
				throw 'reflaxe.ocaml [ocaml-nested-function:conflicting-root-identities]: root function "${binding.functionId}" received more than one whole-body identity lookup';
			return;
		}
		rootIdentityRecordsByFunctionId.set(binding.functionId, {
			binding: copyBinding(binding),
			identities: localIdentities
		});
	}

	/**
		Records one nested literal that is outside the represented-result slice.

		Syntax may retain its older behavior only after this explicit observation.
		If no row exists, planning and syntax did not see the same final body and the
		request fails instead of guessing.
	**/
	public function deferNestedFunction(expression:TypedExpr, identity:OcamlNestedFunctionIdentity, bodyExternalLocals:Array<TVar>,
			observedBodyRevision:String, localIdentities:LexicalLocalIdentityPlan, imapInterfaces:OcamlIMapInterfacePlan, reason:String):Void {
		if (reason.length == 0)
			throw "reflaxe.ocaml [ocaml-nested-function:missing-deferral-reason]: a deferred nested function requires a reason";
		requireNestedFunctionIdentity(expression, identity, observedBodyRevision, localIdentities);
		imapInterfaces.requirePlanBinding(identity.binding);
		storeNestedFunctionRecord(expression, {
			binding: copyBinding(identity.binding),
			parentBinding: copyBinding(identity.parentBinding),
			bodyExternalLocals: bodyExternalLocals.copy(),
			observedBodyRevision: observedBodyRevision,
			occurrenceId: identity.occurrenceId,
			imapInterfaces: imapInterfaces,
			plan: null,
			deferredReason: reason
		}, localIdentities.ownerId);
	}

	/**
		Seals one represented nested function before target syntax starts.

		The parent binding proves which final method owns the literal. The nested
		binding proves which lexical occurrence and body revision own its return,
		loop, throw, and catch decisions. Neither identity may be substituted by
		another parent or request.
	**/
	public function sealNestedFunction(expression:TypedExpr, bodyExternalLocals:Array<TVar>, observedBodyRevision:String, plan:OcamlSealedNestedFunctionPlan,
			localIdentities:LexicalLocalIdentityPlan):Void {
		final identity:OcamlNestedFunctionIdentity = {
			occurrenceId: plan.occurrenceId,
			parentBinding: plan.parentBinding,
			binding: plan.binding
		};
		requireNestedFunctionIdentity(expression, identity, observedBodyRevision, localIdentities);
		OcamlCallPlan.requireCallableBoundary(plan.callableBoundary);
		requireBoundaryBinding(plan.callableBoundary, plan.binding);
		final functionResultBoundary = plan.functionResultBoundary ?? OcamlFunctionResultBoundary.fromCallable(plan.callableBoundary);
		OcamlFunctionResultBoundary.requireCallableMatch(functionResultBoundary, plan.callableBoundary);
		if (plan.callableBoundary.kind != OcamlCallKind.TypedFunctionValue
			|| plan.callableBoundary.resultKind != OcamlCallResultKind.Value
			|| plan.callableBoundary.result == null
			|| plan.callableBoundary.result.conversion != OcamlCallCarrierConversion.Identity
			|| plan.callableBoundary.result.inputSemanticTypeId != plan.callableBoundary.result.outputSemanticTypeId
			|| plan.callableBoundary.result.inputCarrierTypeId != plan.callableBoundary.result.outputCarrierTypeId
			|| plan.callableBoundary.result.inputRepresentationId != plan.callableBoundary.result.outputRepresentationId) {
			throw 'reflaxe.ocaml [ocaml-nested-function:unsupported-boundary]: nested function "${plan.binding.functionId}" is outside the represented callable-result slice';
		}
		plan.controls.requirePlanBinding(plan.binding);
		plan.arrayLiteralProducers.requirePlanBinding(plan.binding);
		plan.imapInterfaces.requirePlanBinding(plan.binding);
		if (!plan.controls.returnFamilyAdmitted || !plan.controls.hasReturnTransfers())
			throw 'reflaxe.ocaml [ocaml-nested-function:missing-return-plan]: nested function "${plan.binding.functionId}" has no admitted early-return transfer';
		// The planner omits unsupported transfers and catch chains. Validate both
		// the family flags and observed catch count so a surviving return cannot
		// hide an unsupported throw, loop transfer, or catch from this catalog.
		if (!plan.controls.loopFamilyAdmitted || !plan.controls.throwFamilyAdmitted)
			throw 'reflaxe.ocaml [ocaml-nested-function:unsupported-control]: nested function "${plan.binding.functionId}" contains an unadmitted loop or throw control family';
		if (plan.controls.catchChains().length != plan.controls.catchOccurrenceCount())
			throw 'reflaxe.ocaml [ocaml-nested-function:unsupported-control]: nested function "${plan.binding.functionId}" contains an unadmitted catch occurrence';
		final returnBoundary = plan.controls.returnBoundaryDecision();
		final returnPayload = returnBoundary == null ? null : returnBoundary.payload;
		final callableResult = plan.callableBoundary.result;
		if (returnBoundary == null
			|| returnPayload == null
			|| callableResult == null
			|| returnPayload.outputSemanticTypeId != callableResult.outputSemanticTypeId
			|| returnPayload.outputCarrierTypeId != callableResult.outputCarrierTypeId
			|| returnPayload.outputRepresentationId != callableResult.outputRepresentationId) {
			throw 'reflaxe.ocaml [ocaml-nested-function:return-boundary-mismatch]: nested function "${plan.binding.functionId}" has callable and control plans for different result carriers';
		}
		final stored:OcamlSealedNestedFunctionPlan = {
			occurrenceId: plan.occurrenceId,
			parentBinding: copyBinding(plan.parentBinding),
			binding: copyBinding(plan.binding),
			callableBoundary: OcamlCallPlan.copyBoundary(plan.callableBoundary),
			functionResultBoundary: OcamlFunctionResultBoundary.copy(functionResultBoundary),
			controls: plan.controls,
			arrayLiteralProducers: plan.arrayLiteralProducers,
			imapInterfaces: plan.imapInterfaces
		};
		storeNestedFunctionRecord(expression, {
			binding: copyBinding(plan.binding),
			parentBinding: copyBinding(plan.parentBinding),
			bodyExternalLocals: bodyExternalLocals.copy(),
			observedBodyRevision: observedBodyRevision,
			occurrenceId: plan.occurrenceId,
			imapInterfaces: plan.imapInterfaces,
			plan: stored,
			deferredReason: null
		}, localIdentities.ownerId);
		nestedFunctionsByOccurrence.set(plan.occurrenceId, stored);
	}

	/**
		Validates the identity that every nested function keeps before syntax starts.

		This validation does not claim that the function's result or control behavior
		is represented. It proves only the stable occurrence, immediate parent, root
		owner, body revision, and current request that syntax can rely on.
	**/
	function requireNestedFunctionIdentity(expression:TypedExpr, identity:OcamlNestedFunctionIdentity, observedBodyRevision:String,
			localIdentities:LexicalLocalIdentityPlan):Void {
		requireCurrentParentBinding(identity.parentBinding);
		if (!LexicalLocalIdentityPlan.isReusableFunctionOccurrenceId(identity.occurrenceId) || identity.binding.functionId.length == 0)
			throw "reflaxe.ocaml [ocaml-nested-function:missing-identity]: a nested function requires stable occurrence and function identities";
		if (observedBodyRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-nested-function:missing-body-revision]: a nested function requires the exact observed body revision";
		final canonicalRoot = rootIdentityRecordsByFunctionId.get(localIdentities.ownerId);
		if (canonicalRoot == null || canonicalRoot.identities != localIdentities)
			throw 'reflaxe.ocaml [ocaml-nested-function:foreign-root-identities]: nested function "${identity.binding.functionId}" does not use the one whole-body identity lookup registered for root "${localIdentities.ownerId}"';
		if (identity.parentBinding.pipelineRevision == PIPELINE_REVISION && !sameBinding(canonicalRoot.binding, identity.parentBinding))
			throw 'reflaxe.ocaml [ocaml-nested-function:stale-root-binding]: nested function "${identity.binding.functionId}" does not use the exact root binding that registered its whole-body identity lookup';
		if (nestedFunctionsByExpression.exists(expression))
			throw 'reflaxe.ocaml [ocaml-nested-function:duplicate-occurrence]: one typed function literal was observed more than once in parent "${identity.parentBinding.functionId}"';
		final expectedOccurrence = try {
			localIdentities.requireFunctionOccurrence(expression);
		} catch (error:Dynamic) {
			throw 'reflaxe.ocaml [ocaml-nested-function:foreign-occurrence]: ${Std.string(error)}';
		}
		final expectedParentOccurrenceId = if (identity.parentBinding.pipelineRevision == PIPELINE_REVISION) {
			null;
		} else {
			final nestedParent = nestedFunctionsByFunctionId.get(identity.parentBinding.functionId);
			nestedParent == null ? null : nestedParent.occurrenceId;
		};
		if (expectedOccurrence.parentOccurrenceId != expectedParentOccurrenceId)
			throw 'reflaxe.ocaml [ocaml-nested-function:foreign-parent-occurrence]: nested function "${identity.binding.functionId}" belongs to parent occurrence "${expectedOccurrence.parentOccurrenceId}", not "${expectedParentOccurrenceId}"';
		final parentUsesLexicalOwner = if (identity.parentBinding.pipelineRevision == PIPELINE_REVISION) {
			identity.parentBinding.functionId == localIdentities.ownerId;
		} else {
			identity.parentBinding.pipelineRevision == NESTED_FUNCTION_PIPELINE_REVISION && nestedFunctionRootOwnerById.get(identity.parentBinding.functionId) == localIdentities.ownerId;
		};
		if (expectedOccurrence.ownerId != localIdentities.ownerId
			|| !parentUsesLexicalOwner
			|| expectedOccurrence.id != identity.occurrenceId) {
			throw 'reflaxe.ocaml [ocaml-nested-function:foreign-occurrence]: nested function "${identity.binding.functionId}" does not use the occurrence assigned to this expression and lexical owner';
		}
		final expectedFunctionId = nestedFunctionId(identity.parentBinding.functionId, identity.occurrenceId);
		if (identity.binding.programRevision != identity.parentBinding.programRevision
			|| identity.binding.pipelineRevision != NESTED_FUNCTION_PIPELINE_REVISION
			|| identity.binding.functionId != expectedFunctionId) {
			throw 'reflaxe.ocaml [ocaml-nested-function:binding-mismatch]: nested function "${identity.binding.functionId}" does not belong to parent "${identity.parentBinding.functionId}"';
		}
		if (nestedFunctionBindingsByOccurrence.exists(identity.occurrenceId))
			throw 'reflaxe.ocaml [ocaml-nested-function:duplicate-identity]: nested occurrence "${identity.occurrenceId}" was observed more than once';
		if (nestedFunctionsByFunctionId.exists(identity.binding.functionId))
			throw 'reflaxe.ocaml [ocaml-nested-function:duplicate-identity]: nested function "${identity.binding.functionId}" was observed more than once';
		if (observedBodyRevision != identity.binding.bodyRevision)
			throw 'reflaxe.ocaml [ocaml-nested-function:stale-body]: nested function "${identity.binding.functionId}" was planned for ${identity.binding.bodyRevision}, but its exact typed body is $observedBodyRevision';
	}

	/** Stores one validated identity after its represented or deferred choice is final. */
	function storeNestedFunctionRecord(expression:TypedExpr, record:OcamlNestedFunctionRecord, rootOwnerId:String):Void {
		nestedFunctionsByExpression.set(expression, record);
		nestedFunctionBindingsByOccurrence.set(record.occurrenceId, copyBinding(record.binding));
		nestedFunctionsByFunctionId.set(record.binding.functionId, record);
		nestedFunctionRootOwnerById.set(record.binding.functionId, rootOwnerId);
	}

	/**
		Returns the plan chosen for one exact typed function occurrence.

		A `null` result means the planner explicitly deferred this occurrence. A
		missing row, changed parent, or stale request is an error because falling back
		there would let syntax choose behavior the planner never authorized.
	**/
	public function nestedFunctionPlanFor(expression:TypedExpr, parentBinding:OcamlFunctionPlanBinding):Null<OcamlSealedNestedFunctionPlan> {
		return nestedFunctionSyntaxDispositionFor(expression, parentBinding).plan;
	}

	/**
		Returns the parent identity and behavior choice for one exact function literal.

		Syntax uses the binding for every observed function body. It uses the optional
		plan only when planning represented the complete result and control behavior.
	**/
	public function nestedFunctionSyntaxDispositionFor(expression:TypedExpr, parentBinding:OcamlFunctionPlanBinding):OcamlNestedFunctionSyntaxDisposition {
		requireCurrentParentBinding(parentBinding);
		final record = nestedFunctionsByExpression.get(expression);
		if (record == null)
			throw 'reflaxe.ocaml [ocaml-nested-function:unobserved-occurrence]: a function literal in parent "${parentBinding.functionId}" reached syntax without a planning disposition';
		if (!sameBinding(record.parentBinding, parentBinding))
			throw 'reflaxe.ocaml [ocaml-nested-function:parent-mismatch]: a function literal planned for "${record.parentBinding.functionId}" was requested by "${parentBinding.functionId}"';
		final observedBodyRevision = observeNestedBodyRevision(expression, record.bodyExternalLocals);
		if (observedBodyRevision != record.observedBodyRevision)
			throw 'reflaxe.ocaml [ocaml-nested-function:stale-body]: a function literal in parent "${parentBinding.functionId}" changed from ${record.observedBodyRevision} to $observedBodyRevision after planning';
		return {
			binding: copyBinding(record.binding),
			imapInterfaces: record.imapInterfaces,
			plan: record.plan
		};
	}

	function requireCurrentParentBinding(binding:OcamlFunctionPlanBinding):Void {
		if (binding.programRevision != currentProgramRevision)
			throw 'reflaxe.ocaml [ocaml-nested-function:stale-parent]: parent "${binding.functionId}" does not belong to current program $currentProgramRevision';
		if (binding.pipelineRevision == PIPELINE_REVISION)
			return;
		if (binding.pipelineRevision == NESTED_FUNCTION_PIPELINE_REVISION) {
			final nestedParent = nestedFunctionsByFunctionId.get(binding.functionId);
			if (nestedParent != null && sameBinding(nestedParent.binding, binding))
				return;
		}
		throw 'reflaxe.ocaml [ocaml-nested-function:stale-parent]: parent "${binding.functionId}" has no current sealed ordinary or nested function binding';
	}

	static function observeNestedBodyRevision(expression:TypedExpr, bodyExternalLocals:Array<TVar>):String {
		return switch (expression.expr) {
			case TFunction(tfunc): FunctionBodyRevision.initial(tfunc.expr, bodyExternalLocals).id;
			case _: throw "reflaxe.ocaml [ocaml-nested-function:not-a-function]: a nested-function catalog entry no longer contains a typed function literal";
		}
	}

	/** Records how one early protection identity became one final plan origin. */
	public function recordProtectionReplacement(protectionId:String, originId:String):Void {
		if (originByProtection.exists(protectionId))
			throw 'reflaxe.ocaml [ocaml-lowering:duplicate-protection-replacement]: early protection "$protectionId" was finalized more than once';
		originByProtection.set(protectionId, originId);
	}

	/** Finds the final origin created from one early protection identity. */
	public function originForProtection(protectionId:String):Null<String> {
		return originByProtection.get(protectionId);
	}

	/** Builds the exact lookup key shared by planning and syntax consumption. */
	public function bindingFor(data:ClassFuncData):OcamlFunctionPlanBinding {
		data.synchronizeBodyRevision();
		return planningBindingFor(data);
	}

	/**
		Captures one binding for a target-owned function-planning session.

		The caller must run inside Reflaxe's revisioned lifecycle, which observes
		the complete body again when the final preprocessor returns. Reusing this
		binding lets one read-only tree walk register every operation without
		re-rendering and hashing the same function once per operation.
	 */
	public function planningBindingFor(data:ClassFuncData):OcamlFunctionPlanBinding {
		final programRevision = data.programRevision;
		if (programRevision == null || programRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-lowering:missing-program-revision]: function "${data.id}" has no program revision';
		if (currentProgramRevision == null || currentProgramRevision != programRevision)
			throw 'reflaxe.ocaml [ocaml-lowering:program-revision-mismatch]: function "${data.id}" belongs to $programRevision, but the plan registry belongs to $currentProgramRevision';
		return {
			functionId: data.id,
			programRevision: programRevision,
			bodyRevision: data.bodyRevision.id,
			pipelineRevision: PIPELINE_REVISION
		};
	}

	/**
		Plans one typed expression emitted outside a function body.

		Class-field initializers and Reflaxe's standalone-expression callback do
		not own `ClassFuncData`, but they still need the same exact program,
		expression-body, and target-pipeline revisions before syntax is built.
	**/
	public function sealStandaloneExpression(ownerId:String, expression:TypedExpr,
			representations:OcamlRepresentationRegistry):OcamlSealedStandaloneExpressionPlan {
		final binding = standaloneBinding("standalone:" + requiredStandaloneOwner(ownerId), expression);
		final containerElements = OcamlContainerElementPlanner.planExpression(expression, binding);
		final anonymousStructures = new OcamlAnonymousStructurePlanner(binding, representations).plan(expression);
		final localIdentities = LexicalLocalIdentityPlan.build(binding.functionId, expression);
		final structuralFields = new OcamlStructuralFieldPlanner(binding, new OcamlCallPlan([]),
			new OcamlIMapInterfacePlan(binding, new haxe.ds.ObjectMap(), new haxe.ds.ObjectMap()), anonymousStructures, representations,
			localIdentities).plan(expression);
		final bytesAccesses = new OcamlBytesAccessPlanner(binding, representations).plan(expression);
		final bytesMutations = new OcamlBytesMutationPlanner(binding, representations).plan(expression);
		final bytesProducers = new OcamlBytesProducerPlanner(binding, representations).plan(expression);
		final bytesReads = new OcamlBytesReadPlanner(binding, representations).plan(expression);
		final reflectCompare = new OcamlReflectComparePlanner(binding).plan(expression);
		containerElements.requirePlanBinding(binding);
		OcamlContainerElementPlanner.requireCompleteness(expression, binding, containerElements);
		anonymousStructures.requirePlanBinding(binding);
		anonymousStructures.requireRepresentations(representations);
		structuralFields.requirePlanBinding(binding);
		bytesAccesses.requirePlanBinding(binding);
		bytesAccesses.requireRepresentations(representations);
		bytesMutations.requirePlanBinding(binding);
		bytesMutations.requireRepresentations(representations);
		bytesProducers.requirePlanBinding(binding);
		bytesProducers.requireRepresentations(representations);
		bytesReads.requirePlanBinding(binding);
		bytesReads.requireRepresentations(representations);
		reflectCompare.requirePlanBinding(binding);
		recordStandaloneContainerElements(containerElements);
		recordStandaloneAnonymousStructures(anonymousStructures);
		recordStandaloneStructuralFields(structuralFields);
		recordStandaloneReflectCompare(reflectCompare);
		return {
			binding: binding,
			containerElements: containerElements,
			anonymousStructures: anonymousStructures,
			structuralFields: structuralFields,
			bytesAccesses: bytesAccesses,
			bytesMutations: bytesMutations,
			bytesProducers: bytesProducers,
			bytesReads: bytesReads,
			reflectCompare: reflectCompare
		};
	}

	/** Keeps report-safe comparison decisions from non-function roots. */
	function recordStandaloneReflectCompare(plan:OcamlReflectComparePlan):Void {
		for (decision in plan.decisions()) {
			final existing = standaloneReflectCompareById.get(decision.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
				throw 'reflaxe.ocaml [ocaml-reflect-compare:conflicting-standalone]: standalone decision "${decision.id}" changed within one request';
			standaloneReflectCompareById.set(decision.id, decision);
		}
	}

	/** Keeps report-safe structural-field decisions from non-function roots. */
	function recordStandaloneStructuralFields(plan:OcamlStructuralFieldPlan):Void {
		for (decision in plan.decisions()) {
			final existing = standaloneStructuralFieldsById.get(decision.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
				throw 'reflaxe.ocaml [ocaml-structural-field:conflicting-standalone]: standalone decision "${decision.id}" changed within one request';
			standaloneStructuralFieldsById.set(decision.id, decision);
		}
	}

	/**
		Keeps report-safe conversion copies from roots emitted outside functions.

		The syntax-facing plan retains exact typed-expression keys for this request.
		The registry publishes only copied decision records, so reports do not keep
		host compiler objects alive or depend on a later body walk.
	**/
	function recordStandaloneContainerElements(plan:OcamlContainerElementPlan):Void {
		for (decision in plan.decisions()) {
			final existing = standaloneContainerElementsById.get(decision.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
				throw 'reflaxe.ocaml [ocaml-container-element:conflicting-standalone-conversion]: standalone conversion "${decision.id}" changed within one compilation request';
			standaloneContainerElementsById.set(decision.id, decision);
		}
		for (id in plan.requiredConversionIds()) {
			if (standaloneRequiredContainerElementIds.exists(id))
				throw 'reflaxe.ocaml [ocaml-container-element:duplicate-standalone-required-conversion]: standalone occurrence "$id" was recorded more than once';
			standaloneRequiredContainerElementIds.set(id, true);
		}
	}

	/**
		Keeps report-safe copies of anonymous-object facts from non-function roots.

		A class-field initializer is emitted outside a normal function plan, but its
		object literal still selects the same `HxAnon` representation and runtime
		operations. Retaining only these immutable JSON-safe decisions lets the final
		lowering report explain that choice without keeping the typed expression or
		replanning it after syntax generation.
	**/
	function recordStandaloneAnonymousStructures(plan:OcamlAnonymousStructurePlan):Void {
		for (structure in plan.structures()) {
			final existing = standaloneAnonymousStructuresById.get(structure.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(structure))
				throw 'reflaxe.ocaml [ocaml-anonymous:conflicting-standalone-structure]: standalone structure "${structure.id}" changed within one compilation request';
			standaloneAnonymousStructuresById.set(structure.id, structure);
		}
		for (operation in plan.operations()) {
			final existing = standaloneAnonymousOperationsById.get(operation.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(operation))
				throw 'reflaxe.ocaml [ocaml-anonymous:conflicting-standalone-operation]: standalone operation "${operation.id}" changed within one compilation request';
			standaloneAnonymousOperationsById.set(operation.id, operation);
		}
	}

	/**
		Rechecks that syntax received the exact standalone expression that was planned.

		The fresh typed-expression digest prevents an in-place mutation between
		planning and syntax construction from reusing a believable stale decision.
	**/
	public function requireStandaloneExpressionPlan(expression:TypedExpr, plan:OcamlSealedStandaloneExpressionPlan,
			representations:OcamlRepresentationRegistry):OcamlSealedStandaloneExpressionPlan {
		if (plan == null)
			throw "reflaxe.ocaml [ocaml-bytes:missing-standalone-plan]: a standalone typed expression reached syntax without its sealed plan";
		final expected = standaloneBinding(plan.binding.functionId, expression);
		if (!sameBinding(plan.binding, expected))
			throw 'reflaxe.ocaml [ocaml-bytes:stale-standalone-plan]: standalone root "${plan.binding.functionId}" was sealed for ${plan.binding.bodyRevision}, but syntax received ${expected.bodyRevision}';
		plan.containerElements.requirePlanBinding(expected);
		OcamlContainerElementPlanner.requireCompleteness(expression, expected, plan.containerElements);
		plan.anonymousStructures.requirePlanBinding(expected);
		plan.anonymousStructures.requireRepresentations(representations);
		plan.structuralFields.requirePlanBinding(expected);
		plan.bytesAccesses.requirePlanBinding(expected);
		plan.bytesAccesses.requireRepresentations(representations);
		plan.bytesMutations.requirePlanBinding(expected);
		plan.bytesMutations.requireRepresentations(representations);
		plan.bytesProducers.requirePlanBinding(expected);
		plan.bytesProducers.requireRepresentations(representations);
		plan.bytesReads.requirePlanBinding(expected);
		plan.bytesReads.requireRepresentations(representations);
		plan.reflectCompare.requirePlanBinding(expected);
		return plan;
	}

	function standaloneBinding(functionId:String, expression:TypedExpr):OcamlFunctionPlanBinding {
		if (!StringTools.startsWith(functionId, "standalone:"))
			throw 'reflaxe.ocaml [ocaml-lowering:invalid-standalone-owner]: standalone root "$functionId" has no standalone identity';
		final programRevision = currentProgramRevision;
		if (programRevision == null || programRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-lowering:missing-program-revision]: standalone root "$functionId" has no program revision';
		return {
			functionId: functionId,
			programRevision: programRevision,
			bodyRevision: FunctionBodyRevision.initial(expression).id,
			pipelineRevision: STANDALONE_PIPELINE_REVISION
		};
	}

	static function requiredStandaloneOwner(ownerId:String):String {
		if (ownerId == null || ownerId.length == 0)
			throw "reflaxe.ocaml [ocaml-lowering:missing-standalone-owner]: a standalone typed expression has no stable owner";
		return ownerId;
	}

	/**
		Observes the final body once and returns every input syntax needs.

		No target callback or typed-expression rewrite may run between this call and
		syntax consumption. Keeping the handoff explicit avoids treating a body
		observation as a reusable cache entry while removing duplicate observations
		from adjacent plan and identity lookups.
	**/
	public function functionSyntaxInputFor(data:ClassFuncData):OcamlFunctionSyntaxInput {
		final sealed = requiredSealedFunctionRecord(data);
		return {
			plan: sealed.plan,
			localIdentities: sealed.localIdentities,
			constructionBoundary: constructionBoundaryForPlan(data, sealed.plan)
		};
	}

	/** Requires the function body reaching syntax construction to remain sealed. */
	public function sealedFunctionPlanFor(data:ClassFuncData):OcamlSealedFunctionPlan {
		return requiredSealedFunctionRecord(data).plan;
	}

	function requiredSealedFunctionRecord(data:ClassFuncData):OcamlSealedFunctionRecord {
		final expected = bindingFor(data);
		final sealed = sealedFunctions.get(data.id);
		if (sealed == null)
			throw 'reflaxe.ocaml [ocaml-lowering:unsealed-function]: function "${data.id}" reached syntax construction without final function-plan validation';
		if (!sameBinding(sealed.plan.binding, expected))
			throw 'reflaxe.ocaml [reflaxe:planned-body-revision-mismatch]: function "${data.id}" was sealed for body ${sealed.plan.binding.bodyRevision}, but syntax construction received ${expected.bodyRevision}';
		return sealed;
	}

	/**
		Returns the request-local lookup that lets syntax consume a stable plan.

		This adapter remains separate because it maps the active host's variable
		objects to stable lexical identities. The sealed function plan is also
		request-local: its container-element lookup keeps exact typed-expression
		keys so syntax cannot confuse macro-generated nodes with equal positions.
		Only copied decision records and generated source bundles may outlive it.
	**/
	public function requestLocalIdentitiesFor(data:ClassFuncData):LexicalLocalIdentityPlan {
		return requiredSealedFunctionRecord(data).localIdentities;
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

	/** Returns the stable origin selected by the typed place planner. */
	public static function originId(operation:OcamlLoweredPlaceOperation):String {
		return switch (operation) {
			case Simple(plan): plan.originId;
			case StaticSimple(plan): plan.originId;
			case ArraySimple(plan): plan.originId;
			case Compound(plan): plan.originId;
			case StaticCompound(plan): plan.originId;
			case ArrayCompound(plan): plan.originId;
			case Update(plan): plan.originId;
			case StaticUpdate(plan): plan.originId;
			case ArrayUpdate(plan): plan.originId;
		}
	}

	/** Returns a concise structural kind for reports and lifecycle fingerprints. */
	public static function nodeKind(operation:OcamlLoweredPlaceOperation):String {
		return switch (operation) {
			case Simple(_): "simple-assignment";
			case StaticSimple(_): "static-simple-assignment";
			case ArraySimple(_): "array-simple-assignment";
			case Compound(_): "compound-assignment";
			case StaticCompound(_): "static-compound-assignment";
			case ArrayCompound(_): "array-compound-assignment";
			case Update(_): "int-update";
			case StaticUpdate(_): "static-int-update";
			case ArrayUpdate(_): "array-int-update";
		}
	}

	/** Adds one already-validated plan to the current function revision. */
	public function register(binding:OcamlFunctionPlanBinding, operation:OcamlLoweredPlaceOperation):OcamlSealedPlacePlan {
		if (sealedFunctions.exists(binding.functionId))
			throw 'reflaxe.ocaml [ocaml-lowering:sealed-function-mutation]: function "${binding.functionId}" received a plan after it was sealed';
		final originId = originId(operation);
		if (plansByOrigin.exists(originId))
			throw 'reflaxe.ocaml [ocaml-lowering:duplicate-origin]: place origin "$originId" was planned more than once';
		final nodeKind = nodeKind(operation);
		final fingerprint = Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			originId,
			nodeKind
		].join("\n"));
		final sealed:OcamlSealedPlacePlan = {
			originId: originId,
			nodeKind: nodeKind,
			fingerprint: fingerprint,
			binding: binding,
			operation: operation
		};
		plansByOrigin.set(originId, sealed);
		final origins = originsByFunction.get(binding.functionId) ?? [];
		origins.push(originId);
		originsByFunction.set(binding.functionId, origins);
		return sealed;
	}

	/** Prevents later planning from silently changing one function's inventory. */
	public function sealFunction(binding:OcamlFunctionPlanBinding, localIdentities:LexicalLocalIdentityPlan, localStorage:OcamlLocalStoragePlan,
			localRepresentations:OcamlLocalRepresentationPlan, containerElements:OcamlContainerElementPlan, bytesAccesses:OcamlBytesAccessPlan,
			bytesMutations:OcamlBytesMutationPlan, bytesProducers:OcamlBytesProducerPlan, bytesReads:OcamlBytesReadPlan,
			imapInterfaces:OcamlIMapInterfacePlan, calls:OcamlCallPlan, controls:OcamlControlPlan, callableBoundary:Null<OcamlCallableBoundaryPlan>,
			functionResultBoundary:Null<OcamlFunctionResultBoundaryPlan>, ?constructionBoundary:Null<OcamlCallableBoundaryPlan>,
			?anonymousStructures:OcamlAnonymousStructurePlan, ?structuralFields:OcamlStructuralFieldPlan,
			?arrayLiteralProducers:OcamlArrayLiteralProducerPlan, ?reflectCompare:OcamlReflectComparePlan):Void {
		if (sealedFunctions.exists(binding.functionId))
			throw 'reflaxe.ocaml [ocaml-lowering:duplicate-function-seal]: function "${binding.functionId}" was sealed more than once';
		final canonicalRoot = rootIdentityRecordsByFunctionId.get(binding.functionId);
		if (canonicalRoot == null) {
			registerRootIdentityPlan(binding, localIdentities);
		} else {
			if (!sameBinding(canonicalRoot.binding, binding))
				throw 'reflaxe.ocaml [ocaml-nested-function:conflicting-root-binding]: sealed function "${binding.functionId}" changed binding after nested planning began';
			if (canonicalRoot.identities != localIdentities)
				throw 'reflaxe.ocaml [ocaml-nested-function:conflicting-root-identities]: sealed function "${binding.functionId}" does not use its registered whole-body identity lookup';
		}
		final sealedAnonymousStructures = anonymousStructures ?? new OcamlAnonymousStructurePlan([], []);
		final sealedStructuralFields = structuralFields ?? new OcamlStructuralFieldPlan([]);
		final sealedArrayLiteralProducers = arrayLiteralProducers ?? new OcamlArrayLiteralProducerPlan([]);
		final sealedReflectCompare = reflectCompare ?? new OcamlReflectComparePlan([]);
		sealedAnonymousStructures.requirePlanBinding(binding);
		sealedStructuralFields.requirePlanBinding(binding);
		bytesAccesses.requirePlanBinding(binding);
		bytesMutations.requirePlanBinding(binding);
		bytesProducers.requirePlanBinding(binding);
		bytesReads.requirePlanBinding(binding);
		imapInterfaces.requirePlanBinding(binding);
		localRepresentations.requirePlanBinding(binding);
		containerElements.requirePlanBinding(binding);
		sealedArrayLiteralProducers.requirePlanBinding(binding);
		for (call in calls.decisions()) {
			OcamlCallPlan.requireCall(call);
			requireCallBinding(call, binding);
			if (requiresDeclaredCallable(call))
				requireCallableDeclaration(call);
		}
		sealedReflectCompare.requirePlanBinding(binding);
		controls.requirePlanBinding(binding);
		if (callableBoundary != null) {
			registerCallableBoundary(callableBoundary, binding);
		}
		if (functionResultBoundary != null) {
			OcamlFunctionResultBoundary.require(functionResultBoundary);
			requireFunctionResultBinding(functionResultBoundary, binding);
			if (callableBoundary != null)
				OcamlFunctionResultBoundary.requireCallableMatch(functionResultBoundary, callableBoundary);
		}
		if (constructionBoundary != null) {
			registerCallableBoundary(constructionBoundary, binding);
		}
		final originIds = (originsByFunction.get(binding.functionId) ?? []).copy();
		originIds.sort(Reflect.compare);
		sealedFunctions.set(binding.functionId, {
			plan: {
				binding: binding,
				localStorage: localStorage,
				localRepresentations: localRepresentations,
				containerElements: containerElements,
				arrayLiteralProducers: sealedArrayLiteralProducers,
				anonymousStructures: sealedAnonymousStructures,
				structuralFields: sealedStructuralFields,
				bytesAccesses: bytesAccesses,
				bytesMutations: bytesMutations,
				bytesProducers: bytesProducers,
				bytesReads: bytesReads,
				imapInterfaces: imapInterfaces,
				calls: calls,
				reflectCompare: sealedReflectCompare,
				controls: controls,
				callableBoundary: callableBoundary == null ? null : OcamlCallPlan.copyBoundary(callableBoundary),
				functionResultBoundary: functionResultBoundary == null ? null : OcamlFunctionResultBoundary.copy(functionResultBoundary),
				constructionBoundary: constructionBoundary == null ? null : OcamlCallPlan.copyBoundary(constructionBoundary)
			},
			localIdentities: localIdentities,
			originIds: originIds
		});
	}

	/** Returns every represented array-literal construction decision in stable order. */
	public function arrayLiteralProducerDecisions():Array<OcamlArrayLiteralProducerDecision> {
		final decisions:Array<OcamlArrayLiteralProducerDecision> = [];
		for (record in sealedFunctions)
			for (decision in record.plan.arrayLiteralProducers.decisions())
				decisions.push(decision);
		for (nested in nestedFunctionsByOccurrence)
			for (decision in nested.arrayLiteralProducers.decisions())
				decisions.push(decision);
		decisions.sort((left, right) -> Reflect.compare(left.id, right.id));
		return decisions;
	}

	function registerCallableBoundary(boundary:OcamlCallableBoundaryPlan, binding:OcamlFunctionPlanBinding):Void {
		OcamlCallPlan.requireCallableBoundary(boundary);
		requireBoundaryBinding(boundary, binding);
		requireDeclarationMatch(boundary);
		if (callableByCallee.exists(boundary.calleeId))
			throw 'reflaxe.ocaml [ocaml-call:duplicate-callable]: callee "${boundary.calleeId}" has more than one sealed callable boundary';
		callableByCallee.set(boundary.calleeId, OcamlCallPlan.copyBoundary(boundary));
	}

	/** Registers one complete typed callable declaration before module emission. */
	public function registerCallableDeclaration(declaration:OcamlCallableDeclarationPlan):Void {
		OcamlCallPlan.requireCallableDeclarationPlan(declaration);
		if (declaration.programRevision != currentProgramRevision || declaration.pipelineRevision != PIPELINE_REVISION)
			throw 'reflaxe.ocaml [ocaml-call:stale-declaration]: callable declaration "${declaration.id}" does not belong to $currentProgramRevision/$PIPELINE_REVISION';
		if (declaredCallableByCallee.exists(declaration.calleeId))
			throw 'reflaxe.ocaml [ocaml-call:duplicate-declaration]: callee "${declaration.calleeId}" has more than one typed declaration';
		declaredCallableByCallee.set(declaration.calleeId, OcamlCallPlan.copyDeclaration(declaration));
	}

	/**
		Reports whether the complete typed program admitted one callable identity.

		This read-only query lets lifecycle and invariant tests distinguish the
		complete declaration catalog from later sealed definition boundaries.
	**/
	public function hasCallableDeclaration(calleeId:String):Bool {
		return declaredCallableByCallee.exists(calleeId);
	}

	/** Returns whether one declaration needs the sealed optional-call hard cut. */
	public function hasOptionalCallableDeclaration(calleeId:String):Bool {
		final declaration = declaredCallableByCallee.get(calleeId);
		return declaration != null && Lambda.exists(declaration.arguments, argument -> argument.parameterOptional);
	}

	/** Returns whether one declaration owns an effect-only `Void` result. */
	public function hasEffectOnlyCallableDeclaration(calleeId:String):Bool {
		final declaration = declaredCallableByCallee.get(calleeId);
		return declaration != null && declaration.resultKind == OcamlCallResultKind.EffectOnlyVoid;
	}

	/** Returns whether one exact constructor must use the sealed construction path. */
	public function hasConstructorDeclaration(calleeId:String):Bool {
		final declaration = declaredCallableByCallee.get(calleeId);
		return declaration != null && declaration.kind == OcamlCallKind.DirectHaxeConstructor;
	}

	/**
		Returns the instance-producing boundary sealed by one constructor body.

		An admitted Haxe constructor is effect-only, while the generated OCaml
		`create` function returns the newly allocated instance. Syntax construction
		must therefore consume this separate boundary instead of treating `new` as
		an ordinary value-returning Haxe method or rereading its typed signature.
	**/
	public function constructionBoundaryForDefinition(data:ClassFuncData):Null<OcamlCallableBoundaryPlan> {
		return functionSyntaxInputFor(data).constructionBoundary;
	}

	function constructionBoundaryForPlan(data:ClassFuncData, sealed:OcamlSealedFunctionPlan):Null<OcamlCallableBoundaryPlan> {
		final calleeId = OcamlCallPlanner.calleeId(data.classType, data.field);
		final boundary = sealed.constructionBoundary;
		if (boundary == null) {
			if (hasConstructorDeclaration(calleeId))
				throw 'reflaxe.ocaml [ocaml-call:missing-construction-boundary]: admitted constructor "$calleeId" reached create syntax without its sealed instance-producing boundary';
			return null;
		}
		if (boundary.kind != OcamlCallKind.DirectHaxeConstructor || boundary.calleeId != calleeId)
			throw 'reflaxe.ocaml [ocaml-call:construction-boundary-mismatch]: function "${data.id}" owns a construction boundary for "${boundary.calleeId}" instead of "$calleeId"';
		final published = callableByCallee.get(calleeId);
		if (published == null
			|| published.id != boundary.id
			|| published.functionId != boundary.functionId
			|| published.bodyRevision != boundary.bodyRevision
			|| published.pipelineRevision != boundary.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-call:unpublished-construction-boundary]: constructor "$calleeId" reached create syntax without its matching published boundary';
		}
		return OcamlCallPlan.copyBoundary(boundary);
	}

	/**
		Requires a caller plan to match the program-wide declaration catalog.

		The catalog is built from the complete typed program before Reflaxe begins
		module syntax. A missing or conflicting call therefore fails before the
		builder constructs target code for that occurrence.
	**/
	public function requireCallableDeclaration(call:OcamlCallDecision):OcamlCallableDeclarationPlan {
		OcamlCallPlan.requireCall(call);
		if (!requiresDeclaredCallable(call))
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: function-value call "${call.id}" does not own a program-wide callable declaration';
		final declaration = declaredCallableByCallee.get(call.calleeId);
		if (declaration == null)
			throw 'reflaxe.ocaml [ocaml-call:missing-declaration]: call "${call.id}" refers to "${call.calleeId}", but the complete typed program has no admitted declaration';
		if (declaration.kind != call.kind
			|| declaration.arguments.length != call.arguments.length
			|| declaration.sourceModuleId != call.sourceModuleId
			|| declaration.sourceTypeName != call.sourceTypeName
			|| declaration.sourceFieldName != call.sourceFieldName
			|| !OcamlCallPlan.sameCallResult(call.resultKind, call.result, declaration.resultKind, declaration.result)
			|| !sameOptionalBoundary(call.receiver, declaration.receiver)) {
			throw 'reflaxe.ocaml [ocaml-call:declaration-mismatch]: call "${call.id}" disagrees with typed declaration "${declaration.id}"';
		}
		for (index in 0...call.arguments.length) {
			if (!OcamlCallPlan.sameCallableBoundary(call.arguments[index], declaration.arguments[index], false))
				throw 'reflaxe.ocaml [ocaml-call:declaration-argument-mismatch]: call "${call.id}" argument $index disagrees with typed declaration "${declaration.id}"';
		}
		return OcamlCallPlan.copyDeclaration(declaration);
	}

	static inline function requiresDeclaredCallable(call:OcamlCallDecision):Bool {
		return call.kind == OcamlCallKind.DirectStaticHaxeMethod
			|| call.kind == OcamlCallKind.DirectInstanceHaxeMethod
			|| call.kind == OcamlCallKind.DirectHaxeConstructor;
	}

	/** Returns every admitted typed call in deterministic identity order. */
	public function callDecisions():Array<OcamlCallDecision> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final calls:Array<OcamlCallDecision> = [];
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (call in sealed.plan.calls.decisions())
					calls.push(call);
			}
		}
		calls.sort((left, right) -> Reflect.compare(left.id, right.id));
		return calls;
	}

	/** Returns every typed `Reflect.compare` decision in deterministic order. */
	public function reflectCompareDecisions():Array<OcamlReflectCompareDecision> {
		final byId:Map<String, OcamlReflectCompareDecision> = [];
		for (decision in standaloneReflectCompareById)
			byId.set(decision.id, decision);
		for (record in sealedFunctions) {
			for (decision in record.plan.reflectCompare.decisions()) {
				final existing = byId.get(decision.id);
				if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
					throw 'reflaxe.ocaml [ocaml-reflect-compare:conflicting-report]: decision "${decision.id}" differs between sealed roots';
				byId.set(decision.id, decision);
			}
		}
		final out = [for (decision in byId) decision];
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every concrete-to-`IMap` conversion in deterministic identity order. */
	public function iMapInterfaceConversions():Array<OcamlIMapInterfaceConversionDecision> {
		final out:Array<OcamlIMapInterfaceConversionDecision> = [];
		for (sealed in sealedFunctions)
			for (conversion in sealed.plan.imapInterfaces.conversions())
				out.push(conversion);
		for (nested in nestedFunctionsByFunctionId)
			for (conversion in nested.imapInterfaces.conversions())
				out.push(conversion);
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every call through a sealed `IMap` interface carrier in stable order. */
	public function iMapInterfaceCalls():Array<OcamlIMapInterfaceCallDecision> {
		final out:Array<OcamlIMapInterfaceCallDecision> = [];
		for (sealed in sealedFunctions)
			for (call in sealed.plan.imapInterfaces.calls())
				out.push(call);
		for (nested in nestedFunctionsByFunctionId)
			for (call in nested.imapInterfaces.calls())
				out.push(call);
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every closed standard-Map storage alias in stable identity order. */
	public function iMapStorageAliases():Array<OcamlIMapStorageAliasDecision> {
		final out:Array<OcamlIMapStorageAliasDecision> = [];
		for (sealed in sealedFunctions)
			for (alias in sealed.plan.imapInterfaces.storageAliases())
				out.push(alias);
		for (nested in nestedFunctionsByFunctionId)
			for (alias in nested.imapInterfaces.storageAliases())
				out.push(alias);
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every admitted control transfer in deterministic identity order. */
	public function controlDecisions():Array<OcamlControlDecision> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final controls:Array<OcamlControlDecision> = [];
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (decision in sealed.plan.controls.decisions())
					controls.push(decision);
			}
		}
		for (nested in nestedFunctionsByOccurrence) {
			for (decision in nested.controls.decisions())
				controls.push(decision);
		}
		controls.sort((left, right) -> Reflect.compare(left.id, right.id));
		return controls;
	}

	/** Returns every admitted lexical loop target in deterministic identity order. */
	public function controlLoopTargets():Array<OcamlControlLoopTarget> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final targets:Array<OcamlControlLoopTarget> = [];
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (target in sealed.plan.controls.loopTargets())
					targets.push(target);
			}
		}
		for (nested in nestedFunctionsByOccurrence) {
			for (target in nested.controls.loopTargets())
				targets.push(target);
		}
		targets.sort((left, right) -> Reflect.compare(left.id, right.id));
		return targets;
	}

	/** Returns every admitted source catch chain in deterministic identity order. */
	public function controlCatchChains():Array<OcamlCatchChainDecision> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final chains:Array<OcamlCatchChainDecision> = [];
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (chain in sealed.plan.controls.catchChains())
					chains.push(chain);
			}
		}
		for (nested in nestedFunctionsByOccurrence) {
			for (chain in nested.controls.catchChains())
				chains.push(chain);
		}
		chains.sort((left, right) -> Reflect.compare(left.id, right.id));
		return chains;
	}

	/**
		Returns the complete typed-control disposition for every sealed function.

		Unlike the admitted decision lists, this inventory also includes functions
		whose return, loop-transfer, throw, or catch family remained on the older
		builder path, together with the planner-owned reason.
	**/
	public function controlAdmissionSnapshots():Array<OcamlControlAdmissionSnapshot> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final snapshots:Array<OcamlControlAdmissionSnapshot> = [];
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null)
				snapshots.push(sealed.plan.controls.admissionSnapshot());
		}
		for (nested in nestedFunctionsByOccurrence)
			snapshots.push(nested.controls.admissionSnapshot());
		snapshots.sort((left, right) -> Reflect.compare(left.id, right.id));
		return snapshots;
	}

	/** Returns every admitted anonymous representation in stable identity order. */
	public function anonymousStructureDecisions():Array<OcamlAnonymousStructureDecision> {
		final byId:Map<String, OcamlAnonymousStructureDecision> = [];
		for (structure in standaloneAnonymousStructuresById)
			byId.set(structure.id, structure);
		for (record in sealedFunctions) {
			for (structure in record.plan.anonymousStructures.structures()) {
				final existing = byId.get(structure.id);
				if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(structure))
					throw 'reflaxe.ocaml [ocaml-anonymous:conflicting-structure]: structure "${structure.id}" differs between sealed functions';
				byId.set(structure.id, structure);
			}
		}
		final out = [for (structure in byId) structure];
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every admitted anonymous operation in stable identity order. */
	public function anonymousStructureOperations():Array<OcamlAnonymousStructureOperationDecision> {
		final byId:Map<String, OcamlAnonymousStructureOperationDecision> = [];
		for (operation in standaloneAnonymousOperationsById)
			byId.set(operation.id, operation);
		for (record in sealedFunctions) {
			for (operation in record.plan.anonymousStructures.operations()) {
				final existing = byId.get(operation.id);
				if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(operation))
					throw 'reflaxe.ocaml [ocaml-anonymous:conflicting-operation]: operation "${operation.id}" differs between sealed roots';
				byId.set(operation.id, operation);
			}
		}
		final out = [for (operation in byId) operation];
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every overlapping structural-field decision in stable order. */
	public function structuralFieldDecisions():Array<OcamlStructuralFieldDecision> {
		final byId:Map<String, OcamlStructuralFieldDecision> = [];
		for (decision in standaloneStructuralFieldsById)
			byId.set(decision.id, decision);
		for (record in sealedFunctions) {
			for (decision in record.plan.structuralFields.decisions()) {
				final existing = byId.get(decision.id);
				if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
					throw 'reflaxe.ocaml [ocaml-structural-field:conflicting]: decision "${decision.id}" differs between sealed roots';
				byId.set(decision.id, decision);
			}
		}
		final out = [for (decision in byId) decision];
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every admitted callable definition in canonical callee order. */
	public function callableBoundaries():Array<OcamlCallableBoundaryPlan> {
		final boundaries:Array<OcamlCallableBoundaryPlan> = [];
		for (boundary in callableByCallee)
			boundaries.push(OcamlCallPlan.copyBoundary(boundary));
		boundaries.sort((left, right) -> Reflect.compare(left.calleeId, right.calleeId));
		return boundaries;
	}

	/** Returns every emitted declaration's completion boundary without treating it as call admission. */
	public function functionResultBoundaries():Array<OcamlFunctionResultBoundaryPlan> {
		final boundaries:Array<OcamlFunctionResultBoundaryPlan> = [];
		for (record in sealedFunctions) {
			if (record.plan.functionResultBoundary != null)
				boundaries.push(OcamlFunctionResultBoundary.copy(record.plan.functionResultBoundary));
		}
		boundaries.sort((left, right) -> Reflect.compare(left.id, right.id));
		return boundaries;
	}

	/**
		Requires an admitted call to agree with the independently sealed callee.

		The complete typed declaration authorizes caller syntax before emission.
		This stricter body check runs once Reflaxe has finalized every function.
		It prevents that earlier declaration check from authorizing a call whose
		final definition failed to publish the matching revision-bound boundary.
	**/
	function requireCallableBoundary(call:OcamlCallDecision):OcamlCallableBoundaryPlan {
		if (!requiresDeclaredCallable(call))
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: function-value call "${call.id}" does not own a program-wide callable boundary';
		final boundary = callableByCallee.get(call.calleeId);
		if (boundary == null) {
			final available = [for (calleeId in callableByCallee.keys()) calleeId];
			available.sort(Reflect.compare);
			throw 'reflaxe.ocaml [ocaml-call:missing-callable]: call "${call.id}" refers to "${call.calleeId}", but that definition has no admitted callable boundary (available: ${available.join(", ")})';
		}
		if (boundary.kind != call.kind
			|| boundary.arguments.length != call.arguments.length
			|| !OcamlCallPlan.sameCallResult(call.resultKind, call.result, boundary.resultKind, boundary.result)
			|| !sameOptionalBoundary(call.receiver, boundary.receiver)) {
			throw 'reflaxe.ocaml [ocaml-call:callable-mismatch]: call "${call.id}" disagrees with callable boundary "${boundary.id}"';
		}
		for (index in 0...call.arguments.length) {
			if (!OcamlCallPlan.sameCallableBoundary(call.arguments[index], boundary.arguments[index], false))
				throw 'reflaxe.ocaml [ocaml-call:argument-mismatch]: call "${call.id}" argument $index disagrees with callable boundary "${boundary.id}"';
		}
		return OcamlCallPlan.copyBoundary(boundary);
	}

	/**
		Validates every caller against the complete independently sealed program.

		Reflaxe finalizes and emits modules lazily, so a caller can reach syntax
		before a later module's definition has been finalized. The target therefore
		performs this mandatory whole-program check immediately before file
		generation, then repeats it before artifact sealing as a lifecycle guard.
	**/
	public function validateCallGraph():Void {
		for (call in callDecisions()) {
			if (requiresDeclaredCallable(call))
				requireCallableBoundary(call);
		}
	}

	/** Returns a function's plans in deterministic origin order. */
	public function plansForFunction(functionId:String):Array<OcamlSealedPlacePlan> {
		final originIds = (originsByFunction.get(functionId) ?? []).copy();
		originIds.sort(Reflect.compare);
		return [for (originId in originIds) cast plansByOrigin.get(originId)];
	}

	/** Returns every sealed local conversion in deterministic identity order. */
	public function localConversions():Array<OcamlLocalConversionDecision> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final conversions:Array<OcamlLocalConversionDecision> = [];
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (conversion in sealed.plan.localRepresentations.conversions())
					conversions.push(conversion);
			}
		}
		conversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		return conversions;
	}

	/** Returns every sealed container-element conversion in deterministic identity order. */
	public function containerElementConversions():Array<OcamlContainerElementDecision> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final conversions:Array<OcamlContainerElementDecision> = [];
		for (conversion in standaloneContainerElementsById)
			conversions.push(conversion);
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (conversion in sealed.plan.containerElements.decisions())
					conversions.push(conversion);
			}
		}
		conversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		return conversions;
	}

	/**
		Returns the independently observed array elements that require conversion.

		The lowering report publishes this inventory separately from the decisions,
		so release tooling can detect a conversion that disappeared together with
		its unsafe-operation and runtime-requirement records.
	**/
	public function containerElementRequiredConversionIds():Array<String> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final required:Array<String> = [];
		final seen:StringMap<Bool> = new StringMap();
		for (id in standaloneRequiredContainerElementIds.keys()) {
			seen.set(id, true);
			required.push(id);
		}
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed == null)
				continue;
			for (id in sealed.plan.containerElements.requiredConversionIds()) {
				if (seen.exists(id))
					throw 'reflaxe.ocaml [ocaml-container-element:duplicate-required-conversion]: occurrence "$id" is required by more than one sealed function';
				seen.set(id, true);
				required.push(id);
			}
		}
		required.sort(Reflect.compare);
		return required;
	}

	/** Returns proof-backed unsafe operations owned by local and container plans. */
	public function unsafeOperations():Array<OcamlUnsafeOperationRecord> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final operations:Array<OcamlUnsafeOperationRecord> = [];
		for (conversion in standaloneContainerElementsById)
			operations.push(conversion.unsafeOperation);
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (operation in sealed.plan.localRepresentations.unsafeOperations())
					operations.push(operation);
				for (operation in sealed.plan.containerElements.unsafeOperations())
					operations.push(operation);
			}
		}
		operations.sort((left, right) -> Reflect.compare(left.id, right.id));
		return operations;
	}

	static function requireCallBinding(call:OcamlCallDecision, binding:OcamlFunctionPlanBinding):Void {
		if (call.functionId != binding.functionId
			|| call.programRevision != binding.programRevision
			|| call.bodyRevision != binding.bodyRevision
			|| call.pipelineRevision != binding.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-call:stale-caller-binding]: call "${call.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
		}
	}

	static function requireBoundaryBinding(boundary:OcamlCallableBoundaryPlan, binding:OcamlFunctionPlanBinding):Void {
		if (boundary.functionId != binding.functionId
			|| boundary.programRevision != binding.programRevision
			|| boundary.bodyRevision != binding.bodyRevision
			|| boundary.pipelineRevision != binding.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-call:stale-callable-binding]: callable boundary "${boundary.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
		}
	}

	static function requireFunctionResultBinding(boundary:OcamlFunctionResultBoundaryPlan, binding:OcamlFunctionPlanBinding):Void {
		if (boundary.functionId != binding.functionId
			|| boundary.programRevision != binding.programRevision
			|| boundary.bodyRevision != binding.bodyRevision
			|| boundary.pipelineRevision != binding.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-function-result:stale-binding]: result boundary "${boundary.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
		}
	}

	function requireDeclarationMatch(boundary:OcamlCallableBoundaryPlan):Void {
		final declaration = declaredCallableByCallee.get(boundary.calleeId);
		if (declaration == null)
			throw 'reflaxe.ocaml [ocaml-call:missing-boundary-declaration]: callable boundary "${boundary.id}" has no program-wide typed declaration';
		if (declaration.kind != boundary.kind
			|| declaration.arguments.length != boundary.arguments.length
			|| declaration.sourceModuleId != boundary.sourceModuleId
			|| declaration.sourceTypeName != boundary.sourceTypeName
			|| declaration.sourceFieldName != boundary.sourceFieldName
			|| !OcamlCallPlan.sameDeclaredResult(boundary.resultKind, boundary.result, declaration.resultKind, declaration.result)
			|| !sameOptionalValue(declaration.receiver, boundary.receiver)) {
			throw 'reflaxe.ocaml [ocaml-call:boundary-declaration-mismatch]: callable boundary "${boundary.id}" disagrees with typed declaration "${declaration.id}"';
		}
		for (index in 0...boundary.arguments.length) {
			if (!OcamlCallPlan.sameValue(declaration.arguments[index], boundary.arguments[index]))
				throw 'reflaxe.ocaml [ocaml-call:boundary-declaration-argument-mismatch]: callable boundary "${boundary.id}" argument $index disagrees with typed declaration "${declaration.id}"';
		}
	}

	static function sameOptionalBoundary(left:Null<OcamlCallValuePlan>, right:Null<OcamlCallValuePlan>):Bool {
		if (left == null || right == null)
			return left == null && right == null;
		return OcamlCallPlan.sameCallableBoundary(left, right, false);
	}

	static function sameOptionalValue(left:Null<OcamlCallValuePlan>, right:Null<OcamlCallValuePlan>):Bool {
		if (left == null || right == null)
			return left == null && right == null;
		return OcamlCallPlan.sameValue(left, right);
	}

	/** Explains a missing or stale lookup instead of allowing emission to guess. */
	public function resolve(originId:String, expected:OcamlFunctionPlanBinding):{plan:Null<OcamlSealedPlacePlan>, error:Null<String>} {
		final plan = plansByOrigin.get(originId);
		if (plan == null)
			return {plan: null, error: 'no sealed plan exists for origin "$originId"'};
		final actual = plan.binding;
		if (!sameBinding(actual, expected)) {
			return {
				plan: null,
				error: 'origin "$originId" belongs to function/body/pipeline ${actual.functionId}/${actual.bodyRevision}/${actual.pipelineRevision}, not ${expected.functionId}/${expected.bodyRevision}/${expected.pipelineRevision}'
			};
		}
		return {plan: plan, error: null};
	}

	/** Verifies the final marker inventory against the sealed function registry. */
	public function validateFunction(data:ClassFuncData, markerOriginIds:Array<String>):Null<String> {
		return validateBinding(bindingFor(data), markerOriginIds);
	}

	/**
		Validates against the body revision most recently observed by the lifecycle.

		This avoids immediately hashing the same body again at the final lifecycle
		callback. Syntax construction still performs a fresh observation so a later
		mutation cannot reuse the sealed plan.
	 */
	public function validateObservedFunction(data:ClassFuncData, markerOriginIds:Array<String>):Null<String> {
		return validateBinding(planningBindingFor(data), markerOriginIds);
	}

	/** Compares one already-captured binding and marker inventory with the seal. */
	public function validateBinding(expected:OcamlFunctionPlanBinding, markerOriginIds:Array<String>):Null<String> {
		final sealed = sealedFunctions.get(expected.functionId);
		if (sealed == null)
			return 'function "${expected.functionId}" has no sealed function-plan inventory';
		if (!sameBinding(sealed.plan.binding, expected)) {
			return
				'[reflaxe:planned-body-revision-mismatch] function "${expected.functionId}" was sealed for body ${sealed.plan.binding.bodyRevision}, but validation received ${expected.bodyRevision}';
		}
		final actualIds = markerOriginIds.copy();
		actualIds.sort(Reflect.compare);
		if (actualIds.length != sealed.originIds.length)
			return 'function "${expected.functionId}" has ${actualIds.length} final origin marker(s), but ${sealed.originIds.length} plan(s) were sealed';
		for (index in 0...actualIds.length) {
			if (actualIds[index] != sealed.originIds[index])
				return 'function "${expected.functionId}" final origin "${actualIds[index]}" does not match sealed plan "${sealed.originIds[index]}"';
		}
		return null;
	}
}
#end
