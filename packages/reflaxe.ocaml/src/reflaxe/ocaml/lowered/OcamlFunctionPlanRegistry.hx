package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;
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
import reflaxe.ocaml.lowered.OcamlArrayReadPlan;
import reflaxe.ocaml.lowered.OcamlArrayReadPlan.OcamlArrayReadPlanner;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorPlanner;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityPlanner;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringPlanner;
import reflaxe.ocaml.lowered.OcamlStaticStringPlan;
import reflaxe.ocaml.lowered.OcamlStaticStringPlan.OcamlStaticStringPlanner;
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
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPlanner;
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
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan.OcamlReflectRuntimeUsePlanner;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan.OcamlStdIsOfTypeDecision;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan.OcamlStdIsOfTypePlanner;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryDecision;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryPlanner;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodeDecision;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodePlanner;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan.OcamlStringEqualityPlanner;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan.OcamlStringMethodPlanner;
import reflaxe.ocaml.lowered.OcamlStringFieldPlan;
import reflaxe.ocaml.lowered.OcamlStringFieldPlan.OcamlStringFieldPlanner;

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
	final arrayReads:OcamlArrayReadPlan;
	final arrayIterators:OcamlArrayIteratorPlan;
	final dynamicEquality:OcamlDynamicEqualityPlan;
	final dynamicString:OcamlDynamicStringPlan;
	final staticString:OcamlStaticStringPlan;
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final structuralFields:OcamlStructuralFieldPlan;
	final bytesAccesses:OcamlBytesAccessPlan;
	final bytesMutations:OcamlBytesMutationPlan;
	final bytesProducers:OcamlBytesProducerPlan;
	final bytesReads:OcamlBytesReadPlan;
	final imapInterfaces:OcamlIMapInterfacePlan;
	final calls:OcamlCallPlan;
	final reflectCompare:OcamlReflectComparePlan;
	final reflectRuntimeUses:OcamlReflectRuntimeUsePlan;
	final stdIsOfType:OcamlStdIsOfTypePlan;
	final intUnary:OcamlIntUnaryPlan;
	final stringFromCharCode:OcamlStringFromCharCodePlan;
	final stringEquality:OcamlStringEqualityPlan;
	final stringMethods:OcamlStringMethodPlan;
	final stringFields:OcamlStringFieldPlan;
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
	final arrayReads:OcamlArrayReadPlan;
	final arrayIterators:OcamlArrayIteratorPlan;
	final dynamicEquality:OcamlDynamicEqualityPlan;
	final ?dynamicString:OcamlDynamicStringPlan;
	final ?staticString:OcamlStaticStringPlan;
	final ?reflectRuntimeUses:OcamlReflectRuntimeUsePlan;
	final ?stdIsOfType:OcamlStdIsOfTypePlan;
	final ?intUnary:OcamlIntUnaryPlan;
	final ?stringFromCharCode:OcamlStringFromCharCodePlan;
	final ?stringEquality:OcamlStringEqualityPlan;
	final ?stringMethods:OcamlStringMethodPlan;
	final ?stringFields:OcamlStringFieldPlan;
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
	Gives syntax the nested function's identity, controls, and optional result plan.

	Every observed literal keeps its own control plan. This lets a deferred closure
	use checked `break`, `continue`, throw, and catch decisions without pretending
	that its return carrier is supported. `plan == null` now defers only the complete
	callable-result path. The binding still becomes the parent while syntax builds
	the body, so a deeper function keeps the correct lexical owner.
**/
typedef OcamlNestedFunctionSyntaxDisposition = {
	final binding:OcamlFunctionPlanBinding;
	final controls:OcamlControlPlan;
	final imapInterfaces:OcamlIMapInterfacePlan;
	final arrayReads:OcamlArrayReadPlan;
	final arrayIterators:OcamlArrayIteratorPlan;
	final dynamicEquality:OcamlDynamicEqualityPlan;
	final ?dynamicString:OcamlDynamicStringPlan;
	final ?staticString:OcamlStaticStringPlan;
	final ?reflectRuntimeUses:OcamlReflectRuntimeUsePlan;
	final ?stdIsOfType:OcamlStdIsOfTypePlan;
	final ?intUnary:OcamlIntUnaryPlan;
	final ?stringFromCharCode:OcamlStringFromCharCodePlan;
	final ?stringEquality:OcamlStringEqualityPlan;
	final ?stringMethods:OcamlStringMethodPlan;
	final ?stringFields:OcamlStringFieldPlan;
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
	final controls:OcamlControlPlan;
	final containerElements:OcamlContainerElementPlan;
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final structuralFields:OcamlStructuralFieldPlan;
	final bytesAccesses:OcamlBytesAccessPlan;
	final bytesMutations:OcamlBytesMutationPlan;
	final bytesProducers:OcamlBytesProducerPlan;
	final bytesReads:OcamlBytesReadPlan;
	final arrayReads:OcamlArrayReadPlan;
	final arrayIterators:OcamlArrayIteratorPlan;
	final dynamicEquality:OcamlDynamicEqualityPlan;
	final dynamicString:OcamlDynamicStringPlan;
	final staticString:OcamlStaticStringPlan;
	final reflectCompare:OcamlReflectComparePlan;
	final reflectRuntimeUses:OcamlReflectRuntimeUsePlan;
	final stdIsOfType:OcamlStdIsOfTypePlan;
	final intUnary:OcamlIntUnaryPlan;
	final stringFromCharCode:OcamlStringFromCharCodePlan;
	final stringEquality:OcamlStringEqualityPlan;
	final stringMethods:OcamlStringMethodPlan;
	final stringFields:OcamlStringFieldPlan;
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

	`controls` always owns the exact request-local control occurrences. `plan ==
	null` is an explicit result-boundary deferral, not a missing observation. This
	distinction lets syntax preserve current return behavior while it consumes the
	loop, throw, and catch decisions that planning can already prove.
**/
private typedef OcamlNestedFunctionRecord = {
	final binding:OcamlFunctionPlanBinding;
	final parentBinding:OcamlFunctionPlanBinding;
	final controls:OcamlControlPlan;
	final occurrenceId:String;
	final imapInterfaces:OcamlIMapInterfacePlan;
	final arrayReads:OcamlArrayReadPlan;
	final arrayIterators:OcamlArrayIteratorPlan;
	final dynamicEquality:OcamlDynamicEqualityPlan;
	final dynamicString:OcamlDynamicStringPlan;
	final staticString:OcamlStaticStringPlan;
	final reflectRuntimeUses:OcamlReflectRuntimeUsePlan;
	final stdIsOfType:OcamlStdIsOfTypePlan;
	final intUnary:OcamlIntUnaryPlan;
	final stringFromCharCode:OcamlStringFromCharCodePlan;
	final stringEquality:OcamlStringEqualityPlan;
	final stringMethods:OcamlStringMethodPlan;
	final stringFields:OcamlStringFieldPlan;
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
	public static inline final PIPELINE_REVISION = "ocaml-function-plans-v112";
	public static inline final NESTED_FUNCTION_PIPELINE_REVISION = "ocaml-nested-function-plans-v32";
	public static inline final STANDALONE_PIPELINE_REVISION = "ocaml-standalone-expression-plans-v15";

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
	final standaloneStdIsOfTypeById:StringMap<OcamlStdIsOfTypeDecision> = new StringMap();
	final standaloneIntUnaryById:StringMap<OcamlIntUnaryDecision> = new StringMap();
	final standaloneStringFromCharCodeById:StringMap<OcamlStringFromCharCodeDecision> = new StringMap();
	final standaloneControlsByFunctionId:StringMap<OcamlControlPlan> = new StringMap();

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
		standaloneStdIsOfTypeById.clear();
		standaloneIntUnaryById.clear();
		standaloneStringFromCharCodeById.clear();
		standaloneControlsByFunctionId.clear();
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
	public function deferNestedFunction(expression:TypedExpr, identity:OcamlNestedFunctionIdentity, localIdentities:LexicalLocalIdentityPlan,
			imapInterfaces:OcamlIMapInterfacePlan, arrayReads:OcamlArrayReadPlan, arrayIterators:OcamlArrayIteratorPlan,
			dynamicEquality:OcamlDynamicEqualityPlan, controls:OcamlControlPlan, reason:String, ?dynamicString:OcamlDynamicStringPlan,
			?staticString:OcamlStaticStringPlan, ?reflectRuntimeUses:OcamlReflectRuntimeUsePlan, ?stdIsOfType:OcamlStdIsOfTypePlan,
			?intUnary:OcamlIntUnaryPlan, ?stringFromCharCode:OcamlStringFromCharCodePlan, ?stringEquality:OcamlStringEqualityPlan,
			?stringMethods:OcamlStringMethodPlan, ?stringFields:OcamlStringFieldPlan):Void {
		if (reason.length == 0)
			throw "reflaxe.ocaml [ocaml-nested-function:missing-deferral-reason]: a deferred nested function requires a reason";
		requireNestedFunctionIdentity(expression, identity, localIdentities);
		imapInterfaces.requirePlanBinding(identity.binding);
		arrayReads.requirePlanBinding(identity.binding);
		arrayIterators.requirePlanBinding(identity.binding);
		dynamicEquality.requirePlanBinding(identity.binding);
		controls.requirePlanBinding(identity.binding);
		final sealedDynamicString = dynamicString ?? new OcamlDynamicStringPlan([]);
		sealedDynamicString.requirePlanBinding(identity.binding);
		final sealedStaticString = staticString ?? new OcamlStaticStringPlan([]);
		sealedStaticString.requirePlanBinding(identity.binding);
		final sealedReflectRuntimeUses = reflectRuntimeUses ?? new OcamlReflectRuntimeUsePlan([]);
		sealedReflectRuntimeUses.requirePlanBinding(identity.binding);
		final sealedStdIsOfType = stdIsOfType ?? new OcamlStdIsOfTypePlan([]);
		sealedStdIsOfType.requirePlanBinding(identity.binding);
		final sealedIntUnary = intUnary ?? new OcamlIntUnaryPlan([]);
		sealedIntUnary.requirePlanBinding(identity.binding);
		final sealedStringFromCharCode = stringFromCharCode ?? new OcamlStringFromCharCodePlan([]);
		sealedStringFromCharCode.requirePlanBinding(identity.binding);
		final sealedStringEquality = stringEquality ?? new OcamlStringEqualityPlan([]);
		sealedStringEquality.requirePlanBinding(identity.binding);
		final sealedStringMethods = stringMethods ?? new OcamlStringMethodPlan([]);
		sealedStringMethods.requirePlanBinding(identity.binding);
		final sealedStringFields = stringFields ?? new OcamlStringFieldPlan([]);
		sealedStringFields.requirePlanBinding(identity.binding);
		storeNestedFunctionRecord(expression, {
			binding: copyBinding(identity.binding),
			parentBinding: copyBinding(identity.parentBinding),
			controls: controls,
			occurrenceId: identity.occurrenceId,
			imapInterfaces: imapInterfaces,
			arrayReads: arrayReads,
			arrayIterators: arrayIterators,
			dynamicEquality: dynamicEquality,
			dynamicString: sealedDynamicString,
			staticString: sealedStaticString,
			reflectRuntimeUses: sealedReflectRuntimeUses,
			stdIsOfType: sealedStdIsOfType,
			intUnary: sealedIntUnary,
			stringFromCharCode: sealedStringFromCharCode,
			stringEquality: sealedStringEquality,
			stringMethods: sealedStringMethods,
			stringFields: sealedStringFields,
			plan: null,
			deferredReason: reason
		}, localIdentities.ownerId);
	}

	/**
		Seals one represented nested function before target syntax starts.

		The parent binding proves which final method owns the literal. The nested
		binding proves which lexical occurrence and exact ordinary-root revision own its return,
		loop, throw, and catch decisions. Neither identity may be substituted by
		another parent or request.
	**/
	public function sealNestedFunction(expression:TypedExpr, plan:OcamlSealedNestedFunctionPlan, localIdentities:LexicalLocalIdentityPlan):Void {
		final identity:OcamlNestedFunctionIdentity = {
			occurrenceId: plan.occurrenceId,
			parentBinding: plan.parentBinding,
			binding: plan.binding
		};
		requireNestedFunctionIdentity(expression, identity, localIdentities);
		OcamlCallPlan.requireCallableBoundary(plan.callableBoundary);
		requireBoundaryBinding(plan.callableBoundary, plan.binding);
		final functionResultBoundary = plan.functionResultBoundary ?? OcamlFunctionResultBoundary.fromCallable(plan.callableBoundary);
		OcamlFunctionResultBoundary.requireCallableMatch(functionResultBoundary, plan.callableBoundary);
		final callableResult = plan.callableBoundary.result;
		final representedResult = callableResult != null
			&& (callableResult.conversion == OcamlCallCarrierConversion.Identity
				&& callableResult.inputSemanticTypeId == callableResult.outputSemanticTypeId
				&& callableResult.inputCarrierTypeId == callableResult.outputCarrierTypeId
				&& callableResult.inputRepresentationId == callableResult.outputRepresentationId
				|| OcamlCallPlan.isExactEnumToNullableResult(callableResult));
		if (plan.callableBoundary.kind != OcamlCallKind.TypedFunctionValue
			|| plan.callableBoundary.resultKind != OcamlCallResultKind.Value
			|| !representedResult) {
			throw 'reflaxe.ocaml [ocaml-nested-function:unsupported-boundary]: nested function "${plan.binding.functionId}" is outside the represented callable-result slice';
		}
		plan.controls.requirePlanBinding(plan.binding);
		plan.arrayLiteralProducers.requirePlanBinding(plan.binding);
		plan.arrayReads.requirePlanBinding(plan.binding);
		plan.arrayIterators.requirePlanBinding(plan.binding);
		plan.dynamicEquality.requirePlanBinding(plan.binding);
		final sealedDynamicString = plan.dynamicString ?? new OcamlDynamicStringPlan([]);
		sealedDynamicString.requirePlanBinding(plan.binding);
		final sealedStaticString = plan.staticString ?? new OcamlStaticStringPlan([]);
		sealedStaticString.requirePlanBinding(plan.binding);
		final sealedReflectRuntimeUses = plan.reflectRuntimeUses ?? new OcamlReflectRuntimeUsePlan([]);
		sealedReflectRuntimeUses.requirePlanBinding(plan.binding);
		final sealedStdIsOfType = plan.stdIsOfType ?? new OcamlStdIsOfTypePlan([]);
		sealedStdIsOfType.requirePlanBinding(plan.binding);
		final sealedIntUnary = plan.intUnary ?? new OcamlIntUnaryPlan([]);
		sealedIntUnary.requirePlanBinding(plan.binding);
		final sealedStringFromCharCode = plan.stringFromCharCode ?? new OcamlStringFromCharCodePlan([]);
		sealedStringFromCharCode.requirePlanBinding(plan.binding);
		final sealedStringEquality = plan.stringEquality ?? new OcamlStringEqualityPlan([]);
		sealedStringEquality.requirePlanBinding(plan.binding);
		final sealedStringMethods = plan.stringMethods ?? new OcamlStringMethodPlan([]);
		sealedStringMethods.requirePlanBinding(plan.binding);
		final sealedStringFields = plan.stringFields ?? new OcamlStringFieldPlan([]);
		sealedStringFields.requirePlanBinding(plan.binding);
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
		if (returnBoundary == null
			|| returnPayload == null
			|| callableResult == null
			|| returnPayload.outputSemanticTypeId != callableResult.outputSemanticTypeId
			|| returnPayload.outputCarrierTypeId != callableResult.outputCarrierTypeId
			|| returnPayload.outputRepresentationId != callableResult.outputRepresentationId) {
			throw 'reflaxe.ocaml [ocaml-nested-function:return-boundary-mismatch]: nested function "${plan.binding.functionId}" has callable and control plans for different result carriers: control=${returnPayload == null ? "missing" : returnPayload.outputSemanticTypeId + "/" + returnPayload.outputCarrierTypeId + "/" + returnPayload.outputRepresentationId}, callable=${callableResult == null ? "missing" : callableResult.outputSemanticTypeId + "/" + callableResult.outputCarrierTypeId + "/" + callableResult.outputRepresentationId}';
		}
		final stored:OcamlSealedNestedFunctionPlan = {
			occurrenceId: plan.occurrenceId,
			parentBinding: copyBinding(plan.parentBinding),
			binding: copyBinding(plan.binding),
			callableBoundary: OcamlCallPlan.copyBoundary(plan.callableBoundary),
			functionResultBoundary: OcamlFunctionResultBoundary.copy(functionResultBoundary),
			controls: plan.controls,
			arrayLiteralProducers: plan.arrayLiteralProducers,
			arrayReads: plan.arrayReads,
			arrayIterators: plan.arrayIterators,
			dynamicEquality: plan.dynamicEquality,
			dynamicString: sealedDynamicString,
			staticString: sealedStaticString,
			reflectRuntimeUses: sealedReflectRuntimeUses,
			stdIsOfType: sealedStdIsOfType,
			intUnary: sealedIntUnary,
			stringFromCharCode: sealedStringFromCharCode,
			stringEquality: sealedStringEquality,
			stringMethods: sealedStringMethods,
			stringFields: sealedStringFields,
			imapInterfaces: plan.imapInterfaces
		};
		storeNestedFunctionRecord(expression, {
			binding: copyBinding(plan.binding),
			parentBinding: copyBinding(plan.parentBinding),
			controls: plan.controls,
			occurrenceId: plan.occurrenceId,
			imapInterfaces: plan.imapInterfaces,
			arrayReads: plan.arrayReads,
			arrayIterators: plan.arrayIterators,
			dynamicEquality: plan.dynamicEquality,
			dynamicString: sealedDynamicString,
			staticString: sealedStaticString,
			reflectRuntimeUses: sealedReflectRuntimeUses,
			stdIsOfType: sealedStdIsOfType,
			intUnary: sealedIntUnary,
			stringFromCharCode: sealedStringFromCharCode,
			stringEquality: sealedStringEquality,
			stringMethods: sealedStringMethods,
			stringFields: sealedStringFields,
			plan: stored,
			deferredReason: null
		}, localIdentities.ownerId);
		nestedFunctionsByOccurrence.set(plan.occurrenceId, stored);
	}

	/**
		Validates the identity that every nested function keeps before syntax starts.

		This validation does not claim that the function's result or control behavior
		is represented. It proves only the stable occurrence, immediate parent, root
		owner, root body revision, and current request that syntax can rely on.
	**/
	function requireNestedFunctionIdentity(expression:TypedExpr, identity:OcamlNestedFunctionIdentity, localIdentities:LexicalLocalIdentityPlan):Void {
		requireCurrentParentBinding(identity.parentBinding);
		if (!LexicalLocalIdentityPlan.isReusableFunctionOccurrenceId(identity.occurrenceId) || identity.binding.functionId.length == 0)
			throw "reflaxe.ocaml [ocaml-nested-function:missing-identity]: a nested function requires stable occurrence and function identities";
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
			|| identity.binding.functionId != expectedFunctionId
			|| identity.binding.bodyRevision != canonicalRoot.binding.bodyRevision
			|| identity.parentBinding.bodyRevision != canonicalRoot.binding.bodyRevision) {
			throw 'reflaxe.ocaml [ocaml-nested-function:binding-mismatch]: nested function "${identity.binding.functionId}" does not belong to parent "${identity.parentBinding.functionId}"';
		}
		if (nestedFunctionBindingsByOccurrence.exists(identity.occurrenceId))
			throw 'reflaxe.ocaml [ocaml-nested-function:duplicate-identity]: nested occurrence "${identity.occurrenceId}" was observed more than once';
		if (nestedFunctionsByFunctionId.exists(identity.binding.functionId))
			throw 'reflaxe.ocaml [ocaml-nested-function:duplicate-identity]: nested function "${identity.binding.functionId}" was observed more than once';
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
	public function nestedFunctionPlanFor(expression:TypedExpr, parentBinding:OcamlFunctionPlanBinding,
			rootBinding:OcamlFunctionPlanBinding):Null<OcamlSealedNestedFunctionPlan> {
		return nestedFunctionSyntaxDispositionFor(expression, parentBinding, rootBinding).plan;
	}

	/**
		Returns the parent identity and behavior choice for one exact function literal.

		The caller supplies the ordinary-root binding that `functionSyntaxInputFor`
		freshly rechecked. Syntax uses the nested binding for every observed function
		body and the optional plan only when planning represented the complete result
		and control behavior.
	**/
	public function nestedFunctionSyntaxDispositionFor(expression:TypedExpr, parentBinding:OcamlFunctionPlanBinding,
			rootBinding:OcamlFunctionPlanBinding):OcamlNestedFunctionSyntaxDisposition {
		requireCurrentParentBinding(parentBinding);
		final record = nestedFunctionsByExpression.get(expression);
		if (record == null)
			throw 'reflaxe.ocaml [ocaml-nested-function:unobserved-occurrence]: a function literal in parent "${parentBinding.functionId}" reached syntax without a planning disposition';
		if (!sameBinding(record.parentBinding, parentBinding))
			throw 'reflaxe.ocaml [ocaml-nested-function:parent-mismatch]: a function literal planned for "${record.parentBinding.functionId}" was requested by "${parentBinding.functionId}"';
		requireCurrentRootSyntaxBinding(rootBinding, record);
		return {
			binding: copyBinding(record.binding),
			controls: record.controls,
			imapInterfaces: record.imapInterfaces,
			arrayReads: record.arrayReads,
			arrayIterators: record.arrayIterators,
			dynamicEquality: record.dynamicEquality,
			dynamicString: record.dynamicString,
			staticString: record.staticString,
			reflectRuntimeUses: record.reflectRuntimeUses,
			stdIsOfType: record.stdIsOfType,
			intUnary: record.intUnary,
			stringFromCharCode: record.stringFromCharCode,
			stringEquality: record.stringEquality,
			stringMethods: record.stringMethods,
			stringFields: record.stringFields,
			plan: record.plan
		};
	}

	/**
		Requires the freshly rechecked ordinary root that authorized syntax construction.

		`functionSyntaxInputFor` observes the complete final root immediately before
		the builder starts. No target callback or typed-tree rewrite may run during
		that handoff, so every nested literal is covered by the same exact revision.
	**/
	function requireCurrentRootSyntaxBinding(rootBinding:OcamlFunctionPlanBinding, record:OcamlNestedFunctionRecord):Void {
		if (rootBinding.pipelineRevision != PIPELINE_REVISION || rootBinding.programRevision != currentProgramRevision)
			throw 'reflaxe.ocaml [ocaml-nested-function:stale-root-binding]: nested function "${record.binding.functionId}" did not receive a current ordinary-root syntax binding';
		final canonicalRoot = rootIdentityRecordsByFunctionId.get(rootBinding.functionId);
		if (canonicalRoot == null || !sameBinding(canonicalRoot.binding, rootBinding))
			throw 'reflaxe.ocaml [ocaml-nested-function:stale-root-binding]: nested function "${record.binding.functionId}" did not receive the exact root binding that registered its whole-body identities';
		if (nestedFunctionRootOwnerById.get(record.binding.functionId) != rootBinding.functionId
			|| record.binding.bodyRevision != rootBinding.bodyRevision
			|| record.parentBinding.bodyRevision != rootBinding.bodyRevision) {
			throw 'reflaxe.ocaml [ocaml-nested-function:foreign-root-binding]: nested function "${record.binding.functionId}" does not belong to freshly checked root "${rootBinding.functionId}"';
		}
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
		final arrayReads = new OcamlArrayReadPlanner(binding).plan(expression);
		final arrayIterators = new OcamlArrayIteratorPlanner(binding).plan(expression);
		final dynamicEquality = new OcamlDynamicEqualityPlanner(binding).plan(expression);
		final dynamicString = new OcamlDynamicStringPlanner(binding).plan(expression);
		final staticString = new OcamlStaticStringPlanner(binding).plan(expression);
		final reflectCompare = new OcamlReflectComparePlanner(binding).plan(expression);
		final reflectRuntimeUses = new OcamlReflectRuntimeUsePlanner(binding).plan(expression);
		final stdIsOfType = new OcamlStdIsOfTypePlanner(binding).plan(expression);
		final intUnary = new OcamlIntUnaryPlanner(binding).plan(expression);
		final stringFromCharCode = new OcamlStringFromCharCodePlanner(binding).plan(expression);
		final stringEquality = new OcamlStringEqualityPlanner(binding).plan(expression);
		final stringMethods = new OcamlStringMethodPlanner(binding).plan(expression);
		final stringFields = new OcamlStringFieldPlanner(binding).plan(expression);
		final controls = new OcamlControlPlanner(representations, new OcamlLocalRepresentationPlan([]), binding, localIdentities).plan(expression, null);
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
		arrayReads.requirePlanBinding(binding);
		arrayIterators.requirePlanBinding(binding);
		dynamicEquality.requirePlanBinding(binding);
		dynamicString.requirePlanBinding(binding);
		staticString.requirePlanBinding(binding);
		bytesReads.requireRepresentations(representations);
		reflectCompare.requirePlanBinding(binding);
		reflectRuntimeUses.requirePlanBinding(binding);
		stdIsOfType.requirePlanBinding(binding);
		intUnary.requirePlanBinding(binding);
		stringFromCharCode.requirePlanBinding(binding);
		stringEquality.requirePlanBinding(binding);
		stringMethods.requirePlanBinding(binding);
		stringFields.requirePlanBinding(binding);
		controls.requirePlanBinding(binding);
		recordStandaloneContainerElements(containerElements);
		recordStandaloneAnonymousStructures(anonymousStructures);
		recordStandaloneStructuralFields(structuralFields);
		recordStandaloneReflectCompare(reflectCompare);
		recordStandaloneStdIsOfType(stdIsOfType);
		recordStandaloneIntUnary(intUnary);
		recordStandaloneStringFromCharCode(stringFromCharCode);
		standaloneControlsByFunctionId.set(binding.functionId, controls);
		return {
			binding: binding,
			controls: controls,
			containerElements: containerElements,
			anonymousStructures: anonymousStructures,
			structuralFields: structuralFields,
			bytesAccesses: bytesAccesses,
			bytesMutations: bytesMutations,
			bytesProducers: bytesProducers,
			bytesReads: bytesReads,
			arrayReads: arrayReads,
			arrayIterators: arrayIterators,
			dynamicEquality: dynamicEquality,
			dynamicString: dynamicString,
			staticString: staticString,
			reflectCompare: reflectCompare,
			reflectRuntimeUses: reflectRuntimeUses,
			stdIsOfType: stdIsOfType,
			intUnary: intUnary,
			stringFromCharCode: stringFromCharCode,
			stringEquality: stringEquality,
			stringMethods: stringMethods,
			stringFields: stringFields
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

	/** Keeps report-safe standard type-check decisions from non-function roots. */
	function recordStandaloneStdIsOfType(plan:OcamlStdIsOfTypePlan):Void {
		for (decision in plan.decisions()) {
			final existing = standaloneStdIsOfTypeById.get(decision.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
				throw 'reflaxe.ocaml [ocaml-std-is-of-type:conflicting-standalone]: standalone decision "${decision.id}" changed within one request';
			standaloneStdIsOfTypeById.set(decision.id, decision);
		}
	}

	/** Keeps report-safe integer-unary decisions from non-function roots. */
	function recordStandaloneIntUnary(plan:OcamlIntUnaryPlan):Void {
		for (decision in plan.decisions()) {
			final existing = standaloneIntUnaryById.get(decision.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
				throw 'reflaxe.ocaml [ocaml-int-unary:conflicting-standalone]: standalone decision "${decision.id}" changed within one request';
			standaloneIntUnaryById.set(decision.id, decision);
		}
	}

	/** Keeps report-safe String character-encoder decisions from non-function roots. */
	function recordStandaloneStringFromCharCode(plan:OcamlStringFromCharCodePlan):Void {
		for (decision in plan.decisions()) {
			final existing = standaloneStringFromCharCodeById.get(decision.id);
			if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
				throw 'reflaxe.ocaml [ocaml-string-from-char-code:conflicting-standalone]: standalone decision "${decision.id}" changed within one request';
			standaloneStringFromCharCodeById.set(decision.id, decision);
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
		plan.arrayReads.requirePlanBinding(expected);
		plan.arrayIterators.requirePlanBinding(expected);
		plan.dynamicEquality.requirePlanBinding(expected);
		plan.dynamicString.requirePlanBinding(expected);
		plan.staticString.requirePlanBinding(expected);
		plan.reflectCompare.requirePlanBinding(expected);
		plan.reflectRuntimeUses.requirePlanBinding(expected);
		plan.stdIsOfType.requirePlanBinding(expected);
		plan.intUnary.requirePlanBinding(expected);
		plan.stringFromCharCode.requirePlanBinding(expected);
		plan.stringEquality.requirePlanBinding(expected);
		plan.stringMethods.requirePlanBinding(expected);
		plan.stringFields.requirePlanBinding(expected);
		plan.controls.requirePlanBinding(expected);
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
			?arrayLiteralProducers:OcamlArrayLiteralProducerPlan, ?reflectCompare:OcamlReflectComparePlan, ?arrayReads:OcamlArrayReadPlan,
			?arrayIterators:OcamlArrayIteratorPlan, ?dynamicEquality:OcamlDynamicEqualityPlan, ?dynamicString:OcamlDynamicStringPlan,
			?staticString:OcamlStaticStringPlan, ?reflectRuntimeUses:OcamlReflectRuntimeUsePlan, ?stdIsOfType:OcamlStdIsOfTypePlan,
			?intUnary:OcamlIntUnaryPlan, ?stringFromCharCode:OcamlStringFromCharCodePlan, ?stringEquality:OcamlStringEqualityPlan,
			?stringMethods:OcamlStringMethodPlan, ?stringFields:OcamlStringFieldPlan):Void {
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
		final sealedArrayReads = arrayReads ?? new OcamlArrayReadPlan([]);
		final sealedArrayIterators = arrayIterators ?? new OcamlArrayIteratorPlan([]);
		final sealedDynamicEquality = dynamicEquality ?? new OcamlDynamicEqualityPlan([]);
		final sealedDynamicString = dynamicString ?? new OcamlDynamicStringPlan([]);
		final sealedStaticString = staticString ?? new OcamlStaticStringPlan([]);
		final sealedReflectRuntimeUses = reflectRuntimeUses ?? new OcamlReflectRuntimeUsePlan([]);
		final sealedStdIsOfType = stdIsOfType ?? new OcamlStdIsOfTypePlan([]);
		final sealedIntUnary = intUnary ?? new OcamlIntUnaryPlan([]);
		final sealedStringFromCharCode = stringFromCharCode ?? new OcamlStringFromCharCodePlan([]);
		final sealedStringEquality = stringEquality ?? new OcamlStringEqualityPlan([]);
		final sealedStringMethods = stringMethods ?? new OcamlStringMethodPlan([]);
		final sealedStringFields = stringFields ?? new OcamlStringFieldPlan([]);
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
		sealedArrayReads.requirePlanBinding(binding);
		sealedArrayIterators.requirePlanBinding(binding);
		sealedDynamicEquality.requirePlanBinding(binding);
		sealedDynamicString.requirePlanBinding(binding);
		sealedStaticString.requirePlanBinding(binding);
		sealedReflectRuntimeUses.requirePlanBinding(binding);
		sealedStdIsOfType.requirePlanBinding(binding);
		sealedIntUnary.requirePlanBinding(binding);
		sealedStringFromCharCode.requirePlanBinding(binding);
		sealedStringEquality.requirePlanBinding(binding);
		sealedStringMethods.requirePlanBinding(binding);
		sealedStringFields.requirePlanBinding(binding);
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
				arrayReads: sealedArrayReads,
				arrayIterators: sealedArrayIterators,
				dynamicEquality: sealedDynamicEquality,
				dynamicString: sealedDynamicString,
				staticString: sealedStaticString,
				anonymousStructures: sealedAnonymousStructures,
				structuralFields: sealedStructuralFields,
				bytesAccesses: bytesAccesses,
				bytesMutations: bytesMutations,
				bytesProducers: bytesProducers,
				bytesReads: bytesReads,
				imapInterfaces: imapInterfaces,
				calls: calls,
				reflectCompare: sealedReflectCompare,
				reflectRuntimeUses: sealedReflectRuntimeUses,
				stdIsOfType: sealedStdIsOfType,
				intUnary: sealedIntUnary,
				stringFromCharCode: sealedStringFromCharCode,
				stringEquality: sealedStringEquality,
				stringMethods: sealedStringMethods,
				stringFields: sealedStringFields,
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

	/** Returns every sealed standard Haxe type check in deterministic order. */
	public function stdIsOfTypeDecisions():Array<OcamlStdIsOfTypeDecision> {
		final byId:Map<String, OcamlStdIsOfTypeDecision> = [];
		for (decision in standaloneStdIsOfTypeById)
			byId.set(decision.id, decision);
		for (record in sealedFunctions)
			for (decision in record.plan.stdIsOfType.decisions())
				recordStdIsOfTypeReportDecision(byId, decision);
		for (record in nestedFunctionsByFunctionId)
			for (decision in record.stdIsOfType.decisions())
				recordStdIsOfTypeReportDecision(byId, decision);
		final out = [for (decision in byId) decision];
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	/** Returns every sealed exact integer unary decision in deterministic order. */
	public function intUnaryDecisions():Array<OcamlIntUnaryDecision> {
		final byId:Map<String, OcamlIntUnaryDecision> = [];
		for (decision in standaloneIntUnaryById)
			byId.set(decision.id, decision);
		for (record in sealedFunctions)
			for (decision in record.plan.intUnary.decisions())
				recordIntUnaryReportDecision(byId, decision);
		for (record in nestedFunctionsByFunctionId)
			for (decision in record.intUnary.decisions())
				recordIntUnaryReportDecision(byId, decision);
		final out = [for (decision in byId) decision];
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	static function recordIntUnaryReportDecision(byId:Map<String, OcamlIntUnaryDecision>, decision:OcamlIntUnaryDecision):Void {
		final existing = byId.get(decision.id);
		if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
			throw 'reflaxe.ocaml [ocaml-int-unary:conflicting-report]: decision "${decision.id}" differs between sealed roots';
		byId.set(decision.id, decision);
	}

	/** Returns every sealed String character-encoder decision in deterministic order. */
	public function stringFromCharCodeDecisions():Array<OcamlStringFromCharCodeDecision> {
		final byId:Map<String, OcamlStringFromCharCodeDecision> = [];
		for (decision in standaloneStringFromCharCodeById)
			byId.set(decision.id, decision);
		for (record in sealedFunctions)
			for (decision in record.plan.stringFromCharCode.decisions())
				recordStringFromCharCodeReportDecision(byId, decision);
		for (record in nestedFunctionsByFunctionId)
			for (decision in record.stringFromCharCode.decisions())
				recordStringFromCharCodeReportDecision(byId, decision);
		final out = [for (decision in byId) decision];
		out.sort((left, right) -> Reflect.compare(left.id, right.id));
		return out;
	}

	static function recordStringFromCharCodeReportDecision(byId:Map<String, OcamlStringFromCharCodeDecision>, decision:OcamlStringFromCharCodeDecision):Void {
		final existing = byId.get(decision.id);
		if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
			throw 'reflaxe.ocaml [ocaml-string-from-char-code:conflicting-report]: decision "${decision.id}" differs between sealed roots';
		byId.set(decision.id, decision);
	}

	static function recordStdIsOfTypeReportDecision(byId:Map<String, OcamlStdIsOfTypeDecision>, decision:OcamlStdIsOfTypeDecision):Void {
		final existing = byId.get(decision.id);
		if (existing != null && haxe.Json.stringify(existing) != haxe.Json.stringify(decision))
			throw 'reflaxe.ocaml [ocaml-std-is-of-type:conflicting-report]: decision "${decision.id}" differs between sealed roots';
		byId.set(decision.id, decision);
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
		for (standalone in standaloneControlsByFunctionId)
			for (decision in standalone.decisions())
				controls.push(decision);
		for (nested in nestedFunctionsByFunctionId) {
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
		for (standalone in standaloneControlsByFunctionId)
			for (target in standalone.loopTargets())
				targets.push(target);
		for (nested in nestedFunctionsByFunctionId) {
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
		for (standalone in standaloneControlsByFunctionId)
			for (chain in standalone.catchChains())
				chains.push(chain);
		for (nested in nestedFunctionsByFunctionId) {
			for (chain in nested.controls.catchChains())
				chains.push(chain);
		}
		chains.sort((left, right) -> Reflect.compare(left.id, right.id));
		return chains;
	}

	/**
		Returns the complete typed-control disposition for every expression owner.

		The owners include ordinary functions, nested function literals, and
		standalone expressions such as field initializers. Unlike the admitted
		decision lists, this inventory also includes a control family that the
		planner rejected, together with the planner-owned reason. Syntax must fail
		closed if it reaches an occurrence from a rejected family.
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
		for (standalone in standaloneControlsByFunctionId)
			snapshots.push(standalone.admissionSnapshot());
		for (nested in nestedFunctionsByFunctionId)
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

	/**
		Returns declaration boundaries and the nested boundaries that have no public
		callable inventory owner.

		Ordinary nested helper results stay internal to their sealed nested plan. The
		nullable-enum slice is reported because its result changes carrier and needs
		independent inspection of that conversion.
	**/
	public function functionResultBoundaries():Array<OcamlFunctionResultBoundaryPlan> {
		final boundaries:Array<OcamlFunctionResultBoundaryPlan> = [];
		for (record in sealedFunctions) {
			if (record.plan.functionResultBoundary != null)
				boundaries.push(OcamlFunctionResultBoundary.copy(record.plan.functionResultBoundary));
		}
		for (record in nestedFunctionsByOccurrence) {
			if (record.functionResultBoundary.source == OcamlFunctionResultBoundarySource.NestedNullableEnumCallable)
				boundaries.push(OcamlFunctionResultBoundary.copy(record.functionResultBoundary));
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
