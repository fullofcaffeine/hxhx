package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;

/** Exact function/body context required when consuming a sealed place plan. */
typedef OcamlPlaceFunctionBinding = {
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One validated target plan that is immutable after its function is sealed. */
typedef OcamlSealedPlacePlan = {
	final originId:String;
	final nodeKind:String;
	final fingerprint:String;
	final binding:OcamlPlaceFunctionBinding;
	final operation:OcamlLoweredPlaceOperation;
}

private typedef OcamlSealedFunction = {
	final binding:OcamlPlaceFunctionBinding;
	final originIds:Array<String>;
}

/**
	Owns revision-bound place plans between final typed preprocessing and syntax.

	A new compilation request clears the registry. Each function is planned and
	validated once, sealed against its exact body revision, and later queried by
	the syntax builder. A mismatch is an internal compiler error, never a request
	to reconstruct source semantics during emission.
**/
class OcamlPlacePlanRegistry {
	public static inline final PIPELINE_REVISION = "ocaml-place-plans-v1";

	var currentProgramRevision:Null<String> = null;
	final plansByOrigin:StringMap<OcamlSealedPlacePlan> = new StringMap();
	final originsByFunction:StringMap<Array<String>> = new StringMap();
	final sealedFunctions:StringMap<OcamlSealedFunction> = new StringMap();
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
	public function bindingFor(data:ClassFuncData):OcamlPlaceFunctionBinding {
		data.synchronizeBodyRevision();
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
	public function sealedBindingFor(data:ClassFuncData):OcamlPlaceFunctionBinding {
		final expected = bindingFor(data);
		final sealed = sealedFunctions.get(data.id);
		if (sealed == null)
			throw 'reflaxe.ocaml [ocaml-lowering:unsealed-function]: function "${data.id}" reached syntax construction without final place-plan validation';
		if (!sameBinding(sealed.binding, expected))
			throw 'reflaxe.ocaml [reflaxe:planned-body-revision-mismatch]: function "${data.id}" was sealed for body ${sealed.binding.bodyRevision}, but syntax construction received ${expected.bodyRevision}';
		return expected;
	}

	static function sameBinding(left:OcamlPlaceFunctionBinding, right:OcamlPlaceFunctionBinding):Bool {
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
	public function register(data:ClassFuncData, operation:OcamlLoweredPlaceOperation):OcamlSealedPlacePlan {
		if (sealedFunctions.exists(data.id))
			throw 'reflaxe.ocaml [ocaml-lowering:sealed-function-mutation]: function "${data.id}" received a plan after it was sealed';
		final binding = bindingFor(data);
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
		final origins = originsByFunction.get(data.id) ?? [];
		origins.push(originId);
		originsByFunction.set(data.id, origins);
		return sealed;
	}

	/** Prevents later planning from silently changing one function's inventory. */
	public function sealFunction(data:ClassFuncData):Void {
		if (sealedFunctions.exists(data.id))
			throw 'reflaxe.ocaml [ocaml-lowering:duplicate-function-seal]: function "${data.id}" was sealed more than once';
		final binding = bindingFor(data);
		final originIds = (originsByFunction.get(data.id) ?? []).copy();
		originIds.sort(Reflect.compare);
		sealedFunctions.set(data.id, {binding: binding, originIds: originIds});
	}

	/** Returns a function's plans in deterministic origin order. */
	public function plansForFunction(functionId:String):Array<OcamlSealedPlacePlan> {
		final originIds = (originsByFunction.get(functionId) ?? []).copy();
		originIds.sort(Reflect.compare);
		return [for (originId in originIds) cast plansByOrigin.get(originId)];
	}

	/** Explains a missing or stale lookup instead of allowing emission to guess. */
	public function resolve(originId:String, expected:OcamlPlaceFunctionBinding):{plan:Null<OcamlSealedPlacePlan>, error:Null<String>} {
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
		final sealed = sealedFunctions.get(data.id);
		if (sealed == null)
			return 'function "${data.id}" has no sealed place-plan inventory';
		final expected = bindingFor(data);
		if (!sameBinding(sealed.binding, expected)) {
			return
				'[reflaxe:planned-body-revision-mismatch] function "${data.id}" was sealed for body ${sealed.binding.bodyRevision}, but validation received ${expected.bodyRevision}';
		}
		final actualIds = markerOriginIds.copy();
		actualIds.sort(Reflect.compare);
		if (actualIds.length != sealed.originIds.length)
			return 'function "${data.id}" has ${actualIds.length} final origin marker(s), but ${sealed.originIds.length} plan(s) were sealed';
		for (index in 0...actualIds.length) {
			if (actualIds[index] != sealed.originIds[index])
				return 'function "${data.id}" final origin "${actualIds[index]}" does not match sealed plan "${sealed.originIds[index]}"';
		}
		return null;
	}
}
#end
