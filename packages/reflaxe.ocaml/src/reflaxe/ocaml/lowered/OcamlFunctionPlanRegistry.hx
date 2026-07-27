package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableDeclarationPlan;
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

/** All target-owned decisions sealed for one exact final function body. */
typedef OcamlSealedFunctionPlan = {
	final binding:OcamlFunctionPlanBinding;
	final localStorage:OcamlLocalStoragePlan;
	final localRepresentations:OcamlLocalRepresentationPlan;
	final calls:OcamlCallPlan;
	final callableBoundary:Null<OcamlCallableBoundaryPlan>;
}

private typedef OcamlSealedFunctionRecord = {
	final plan:OcamlSealedFunctionPlan;
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
	public static inline final PIPELINE_REVISION = "ocaml-function-plans-v19";

	var currentProgramRevision:Null<String> = null;
	final plansByOrigin:StringMap<OcamlSealedPlacePlan> = new StringMap();
	final originsByFunction:StringMap<Array<String>> = new StringMap();
	final sealedFunctions:StringMap<OcamlSealedFunctionRecord> = new StringMap();
	final declaredCallableByCallee:StringMap<OcamlCallableDeclarationPlan> = new StringMap();
	final callableByCallee:StringMap<OcamlCallableBoundaryPlan> = new StringMap();
	final originByProtection:StringMap<String> = new StringMap();

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

	/** Requires the function body reaching syntax construction to remain sealed. */
	public function sealedFunctionPlanFor(data:ClassFuncData):OcamlSealedFunctionPlan {
		final expected = bindingFor(data);
		final sealed = sealedFunctions.get(data.id);
		if (sealed == null)
			throw 'reflaxe.ocaml [ocaml-lowering:unsealed-function]: function "${data.id}" reached syntax construction without final function-plan validation';
		if (!sameBinding(sealed.plan.binding, expected))
			throw 'reflaxe.ocaml [reflaxe:planned-body-revision-mismatch]: function "${data.id}" was sealed for body ${sealed.plan.binding.bodyRevision}, but syntax construction received ${expected.bodyRevision}';
		return sealed.plan;
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
	public function sealFunction(binding:OcamlFunctionPlanBinding, localStorage:OcamlLocalStoragePlan, localRepresentations:OcamlLocalRepresentationPlan,
			calls:OcamlCallPlan, callableBoundary:Null<OcamlCallableBoundaryPlan>):Void {
		if (sealedFunctions.exists(binding.functionId))
			throw 'reflaxe.ocaml [ocaml-lowering:duplicate-function-seal]: function "${binding.functionId}" was sealed more than once';
		for (call in calls.decisions()) {
			OcamlCallPlan.requireDirectStaticCall(call);
			requireCallBinding(call, binding);
			requireCallableDeclaration(call);
		}
		if (callableBoundary != null) {
			OcamlCallPlan.requireDirectStaticBoundary(callableBoundary);
			requireBoundaryBinding(callableBoundary, binding);
			requireDeclarationMatch(callableBoundary);
			if (callableByCallee.exists(callableBoundary.calleeId))
				throw 'reflaxe.ocaml [ocaml-call:duplicate-callable]: callee "${callableBoundary.calleeId}" has more than one sealed callable boundary';
			callableByCallee.set(callableBoundary.calleeId, OcamlCallPlan.copyBoundary(callableBoundary));
		}
		final originIds = (originsByFunction.get(binding.functionId) ?? []).copy();
		originIds.sort(Reflect.compare);
		sealedFunctions.set(binding.functionId, {
			plan: {
				binding: binding,
				localStorage: localStorage,
				localRepresentations: localRepresentations,
				calls: calls,
				callableBoundary: callableBoundary == null ? null : OcamlCallPlan.copyBoundary(callableBoundary)
			},
			originIds: originIds
		});
	}

	/** Registers one complete typed callable declaration before module emission. */
	public function registerCallableDeclaration(declaration:OcamlCallableDeclarationPlan):Void {
		OcamlCallPlan.requireDirectStaticDeclaration(declaration);
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

	/**
		Requires a caller plan to match the program-wide declaration catalog.

		The catalog is built from the complete typed program before Reflaxe begins
		module syntax. A missing or conflicting call therefore fails before the
		builder constructs target code for that occurrence.
	**/
	public function requireCallableDeclaration(call:OcamlCallDecision):OcamlCallableDeclarationPlan {
		OcamlCallPlan.requireDirectStaticCall(call);
		final declaration = declaredCallableByCallee.get(call.calleeId);
		if (declaration == null)
			throw 'reflaxe.ocaml [ocaml-call:missing-declaration]: call "${call.id}" refers to "${call.calleeId}", but the complete typed program has no admitted declaration';
		if (declaration.kind != call.kind
			|| declaration.arguments.length != call.arguments.length
			|| declaration.sourceModuleId != call.sourceModuleId
			|| declaration.sourceTypeName != call.sourceTypeName
			|| declaration.sourceFieldName != call.sourceFieldName
			|| !OcamlCallPlan.sameCallResult(call.resultKind, call.result, declaration.resultKind, declaration.result)) {
			throw 'reflaxe.ocaml [ocaml-call:declaration-mismatch]: call "${call.id}" disagrees with typed declaration "${declaration.id}"';
		}
		for (index in 0...call.arguments.length) {
			if (!OcamlCallPlan.sameCallableBoundary(call.arguments[index], declaration.arguments[index], false))
				throw 'reflaxe.ocaml [ocaml-call:declaration-argument-mismatch]: call "${call.id}" argument $index disagrees with typed declaration "${declaration.id}"';
		}
		return OcamlCallPlan.copyDeclaration(declaration);
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
		final boundary = callableByCallee.get(call.calleeId);
		if (boundary == null) {
			final available = [for (calleeId in callableByCallee.keys()) calleeId];
			available.sort(Reflect.compare);
			throw 'reflaxe.ocaml [ocaml-call:missing-callable]: call "${call.id}" refers to "${call.calleeId}", but that definition has no admitted callable boundary (available: ${available.join(", ")})';
		}
		if (boundary.kind != call.kind
			|| boundary.arguments.length != call.arguments.length
			|| !OcamlCallPlan.sameCallResult(call.resultKind, call.result, boundary.resultKind, boundary.result)) {
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
		for (call in callDecisions())
			requireCallableBoundary(call);
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

	/** Returns the proof-backed unsafe operations owned by sealed local plans. */
	public function unsafeOperations():Array<OcamlUnsafeOperationRecord> {
		final functionIds = [for (functionId in sealedFunctions.keys()) functionId];
		functionIds.sort(Reflect.compare);
		final operations:Array<OcamlUnsafeOperationRecord> = [];
		for (functionId in functionIds) {
			final sealed = sealedFunctions.get(functionId);
			if (sealed != null) {
				for (operation in sealed.plan.localRepresentations.unsafeOperations())
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
			|| !OcamlCallPlan.sameDeclaredResult(boundary.resultKind, boundary.result, declaration.resultKind, declaration.result)) {
			throw 'reflaxe.ocaml [ocaml-call:boundary-declaration-mismatch]: callable boundary "${boundary.id}" disagrees with typed declaration "${declaration.id}"';
		}
		for (index in 0...boundary.arguments.length) {
			if (!OcamlCallPlan.sameValue(declaration.arguments[index], boundary.arguments[index]))
				throw 'reflaxe.ocaml [ocaml-call:boundary-declaration-argument-mismatch]: callable boundary "${boundary.id}" argument $index disagrees with typed declaration "${declaration.id}"';
		}
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
