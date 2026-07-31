package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import haxe.macro.Type.TypedExpr;
import reflaxe.data.ClassFuncData;
import reflaxe.lifecycle.FunctionBodyRevision;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableDeclarationPlan;
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
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationRecord;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;

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
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final bytesAccesses:OcamlBytesAccessPlan;
	final bytesMutations:OcamlBytesMutationPlan;
	final bytesProducers:OcamlBytesProducerPlan;
	final bytesReads:OcamlBytesReadPlan;
	final calls:OcamlCallPlan;
	final controls:OcamlControlPlan;
	final callableBoundary:Null<OcamlCallableBoundaryPlan>;
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
	All target-owned decisions sealed for one exact non-function expression root.

	`binding.functionId` contains a stable root identity even though the shared
	binding schema predates standalone roots. This keeps the producer contract
	revision-bound without pretending that a field initializer is a function.
**/
typedef OcamlSealedStandaloneExpressionPlan = {
	final binding:OcamlFunctionPlanBinding;
	final containerElements:OcamlContainerElementPlan;
	final anonymousStructures:OcamlAnonymousStructurePlan;
	final bytesAccesses:OcamlBytesAccessPlan;
	final bytesMutations:OcamlBytesMutationPlan;
	final bytesProducers:OcamlBytesProducerPlan;
	final bytesReads:OcamlBytesReadPlan;
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
	Owns revision-bound lowered plans between final typed preprocessing and syntax.

	A new compilation request clears the registry. Each function is planned and
	validated once, then its place operations, local-storage choices, and
	occurrence-bound carrier conversions are sealed against the exact body
	revision. A mismatch is an internal compiler error, never a request to
	reconstruct source semantics during emission.
**/
class OcamlFunctionPlanRegistry {
	public static inline final PIPELINE_REVISION = "ocaml-function-plans-v62";
	public static inline final STANDALONE_PIPELINE_REVISION = "ocaml-standalone-expression-plans-v2";

	var currentProgramRevision:Null<String> = null;
	final plansByOrigin:StringMap<OcamlSealedPlacePlan> = new StringMap();
	final originsByFunction:StringMap<Array<String>> = new StringMap();
	final sealedFunctions:StringMap<OcamlSealedFunctionRecord> = new StringMap();
	final declaredCallableByCallee:StringMap<OcamlCallableDeclarationPlan> = new StringMap();
	final callableByCallee:StringMap<OcamlCallableBoundaryPlan> = new StringMap();
	final originByProtection:StringMap<String> = new StringMap();
	final standaloneContainerElementsById:StringMap<OcamlContainerElementDecision> = new StringMap();
	final standaloneRequiredContainerElementIds:StringMap<Bool> = new StringMap();
	final standaloneAnonymousStructuresById:StringMap<OcamlAnonymousStructureDecision> = new StringMap();
	final standaloneAnonymousOperationsById:StringMap<OcamlAnonymousStructureOperationDecision> = new StringMap();

	public function new() {}

	/** Starts one request and discards every prior function plan. */
	public function beginProgram(programRevision:String):Void {
		if (programRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-lowering:missing-program-revision]: the target-selected program revision is empty";
		currentProgramRevision = programRevision;
		plansByOrigin.clear();
		originsByFunction.clear();
		sealedFunctions.clear();
		declaredCallableByCallee.clear();
		callableByCallee.clear();
		originByProtection.clear();
		standaloneContainerElementsById.clear();
		standaloneRequiredContainerElementIds.clear();
		standaloneAnonymousStructuresById.clear();
		standaloneAnonymousOperationsById.clear();
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
		final bytesAccesses = new OcamlBytesAccessPlanner(binding, representations).plan(expression);
		final bytesMutations = new OcamlBytesMutationPlanner(binding, representations).plan(expression);
		final bytesProducers = new OcamlBytesProducerPlanner(binding, representations).plan(expression);
		final bytesReads = new OcamlBytesReadPlanner(binding, representations).plan(expression);
		containerElements.requirePlanBinding(binding);
		OcamlContainerElementPlanner.requireCompleteness(expression, binding, containerElements);
		anonymousStructures.requirePlanBinding(binding);
		anonymousStructures.requireRepresentations(representations);
		bytesAccesses.requirePlanBinding(binding);
		bytesAccesses.requireRepresentations(representations);
		bytesMutations.requirePlanBinding(binding);
		bytesMutations.requireRepresentations(representations);
		bytesProducers.requirePlanBinding(binding);
		bytesProducers.requireRepresentations(representations);
		bytesReads.requirePlanBinding(binding);
		bytesReads.requireRepresentations(representations);
		recordStandaloneContainerElements(containerElements);
		recordStandaloneAnonymousStructures(anonymousStructures);
		return {
			binding: binding,
			containerElements: containerElements,
			anonymousStructures: anonymousStructures,
			bytesAccesses: bytesAccesses,
			bytesMutations: bytesMutations,
			bytesProducers: bytesProducers,
			bytesReads: bytesReads
		};
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
		plan.bytesAccesses.requirePlanBinding(expected);
		plan.bytesAccesses.requireRepresentations(representations);
		plan.bytesMutations.requirePlanBinding(expected);
		plan.bytesMutations.requireRepresentations(representations);
		plan.bytesProducers.requirePlanBinding(expected);
		plan.bytesProducers.requireRepresentations(representations);
		plan.bytesReads.requirePlanBinding(expected);
		plan.bytesReads.requireRepresentations(representations);
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
			bytesMutations:OcamlBytesMutationPlan, bytesProducers:OcamlBytesProducerPlan, bytesReads:OcamlBytesReadPlan, calls:OcamlCallPlan,
			controls:OcamlControlPlan, callableBoundary:Null<OcamlCallableBoundaryPlan>, ?constructionBoundary:Null<OcamlCallableBoundaryPlan>,
			?anonymousStructures:OcamlAnonymousStructurePlan):Void {
		if (sealedFunctions.exists(binding.functionId))
			throw 'reflaxe.ocaml [ocaml-lowering:duplicate-function-seal]: function "${binding.functionId}" was sealed more than once';
		final sealedAnonymousStructures = anonymousStructures ?? new OcamlAnonymousStructurePlan([], []);
		sealedAnonymousStructures.requirePlanBinding(binding);
		bytesAccesses.requirePlanBinding(binding);
		bytesMutations.requirePlanBinding(binding);
		bytesProducers.requirePlanBinding(binding);
		bytesReads.requirePlanBinding(binding);
		localRepresentations.requirePlanBinding(binding);
		containerElements.requirePlanBinding(binding);
		for (call in calls.decisions()) {
			OcamlCallPlan.requireCall(call);
			requireCallBinding(call, binding);
			if (requiresDeclaredCallable(call))
				requireCallableDeclaration(call);
		}
		controls.requirePlanBinding(binding);
		if (callableBoundary != null) {
			registerCallableBoundary(callableBoundary, binding);
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
				anonymousStructures: sealedAnonymousStructures,
				bytesAccesses: bytesAccesses,
				bytesMutations: bytesMutations,
				bytesProducers: bytesProducers,
				bytesReads: bytesReads,
				calls: calls,
				controls: controls,
				callableBoundary: callableBoundary == null ? null : OcamlCallPlan.copyBoundary(callableBoundary),
				constructionBoundary: constructionBoundary == null ? null : OcamlCallPlan.copyBoundary(constructionBoundary)
			},
			localIdentities: localIdentities,
			originIds: originIds
		});
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
		chains.sort((left, right) -> Reflect.compare(left.id, right.id));
		return chains;
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

	/** Returns every admitted callable definition in canonical callee order. */
	public function callableBoundaries():Array<OcamlCallableBoundaryPlan> {
		final boundaries:Array<OcamlCallableBoundaryPlan> = [];
		for (boundary in callableByCallee)
			boundaries.push(OcamlCallPlan.copyBoundary(boundary));
		boundaries.sort((left, right) -> Reflect.compare(left.calleeId, right.calleeId));
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
