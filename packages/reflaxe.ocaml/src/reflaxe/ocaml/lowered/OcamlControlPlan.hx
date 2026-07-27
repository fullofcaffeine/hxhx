package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** The source-language control transfer selected before OCaml syntax. */
enum abstract OcamlControlTransferKind(String) from String to String {
	final Return = "return";
}

/** The observable control effect owned by one sealed transfer. */
enum abstract OcamlControlEffect(String) from String to String {
	final ExitFunction = "exit-function";
}

/** The target mechanism selected for an admitted control transfer. */
enum abstract OcamlControlTargetMechanism(String) from String to String {
	final RuntimeReturnSignal = "runtime-return-signal";
}

/** How an exact Haxe value crosses the private runtime-control payload. */
enum abstract OcamlControlPayloadConversion(String) from String to String {
	final BoxAndRecoverExactValue = "box-and-recover-exact-value";
}

/**
	The complete payload contract for one admitted non-local control transfer.

	The source and target sides are ordinary represented Haxe values. The signal
	carrier is private OCaml runtime plumbing and cannot become the callable's
	public result carrier.
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
	final proofId:String;
	final proofClaim:String;
}

/** One revision-bound early return owned by an exact Haxe function. */
typedef OcamlControlDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlControlTransferKind;
	final effect:OcamlControlEffect;
	final targetFunctionId:String;
	final payload:OcamlControlPayloadPlan;
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
	Immutable control inventory for one final function body.

	`admittedFunction` distinguishes an exact represented function with no early
	returns from a function that is still on the legacy control path. Syntax may
	consume decisions but cannot add or reinterpret them.
**/
class OcamlControlPlan {
	public static inline final EXACT_VALUE_RETURN_PROOF_ID = "exact-value-early-return-control-v2";
	public static inline final RETURN_SIGNAL_CAPABILITY_ID = "hxhx-runtime:function-return-signal-v1";

	public final admittedFunction:Bool;
	public final binding:OcamlFunctionPlanBinding;
	public final revision:String;

	final ordered:Array<OcamlControlDecision>;
	final bySourceKey:Map<String, Array<OcamlControlDecision>> = [];

	public function new(admittedFunction:Bool, binding:OcamlFunctionPlanBinding, decisions:Array<OcamlControlDecision>) {
		this.admittedFunction = admittedFunction;
		this.binding = copyBinding(binding);
		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalized:Array<OcamlControlDecision> = [];
		for (decision in sorted) {
			requireDecision(decision);
			requireBinding(decision, binding);
			if (!admittedFunction)
				throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: unadmitted function "${binding.functionId}" cannot own control decision "${decision.id}"';
			final key = sourceKey(decision.source);
			final candidates = bySourceKey.get(key) ?? [];
			if (Lambda.exists(candidates, existing -> existing.id == decision.id))
				throw 'reflaxe.ocaml [ocaml-control:duplicate-decision]: control identity "${decision.id}" occurs more than once';
			if (candidates.length > 0)
				throw 'reflaxe.ocaml [ocaml-control:duplicate-source-occurrence]: more than one admitted return belongs to source occurrence "$key"';
			candidates.push(copyDecision(decision));
			bySourceKey.set(key, candidates);
			normalized.push(copyDecision(decision));
		}
		ordered = normalized;
		revision = "sha256:" + Sha256.encode([
			admittedFunction ? "admitted" : "legacy",
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision
		].concat(ordered.map(decisionFingerprint)).join("\n"));
	}

	/** Creates an explicit empty plan for a function outside this control slice. */
	public static function notAdmitted(binding:OcamlFunctionPlanBinding):OcamlControlPlan {
		return new OcamlControlPlan(false, binding, []);
	}

	/** Returns immutable copies in deterministic identity order. */
	public function decisions():Array<OcamlControlDecision> {
		return ordered.map(copyDecision);
	}

	/** Whether syntax must install the sealed private return-signal boundary. */
	public inline function hasReturnTransfers():Bool {
		return ordered.length > 0;
	}

	/** Resolves one exact typed return occurrence without inventing a fallback. */
	public function decisionFor(expression:TypedExpr):Null<OcamlControlDecision> {
		final candidates = bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		final matching = candidates.filter(decision -> switch (expression.expr) {
			case TReturn(value): value != null && decision.kind == OcamlControlTransferKind.Return && expressionMatchesPayload(value, decision.payload);
			case _:
				false;
		});
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-control:ambiguous-source-occurrence]: ${matching.length} sealed returns match one typed occurrence at ${sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))}';
		return matching.length == 0 ? null : copyDecision(matching[0]);
	}

	/** Returns the shared return payload contract for the function boundary. */
	public function returnBoundaryDecision():Null<OcamlControlDecision> {
		if (ordered.length == 0)
			return null;
		final first = ordered[0];
		for (decision in ordered) {
			if (payloadFingerprint(decision.payload) != payloadFingerprint(first.payload)
				|| decision.targetFunctionId != first.targetFunctionId
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
		for (decision in ordered)
			requireBinding(decision, expected);
	}

	/** Validates one record independently for corruption and report tests. */
	public static function requireDecision(decision:OcamlControlDecision):Void {
		if (decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.targetFunctionId.length == 0
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: control decision "${decision.id}" has an incomplete identity, source, target, or revision';
		}
		if (decision.kind != OcamlControlTransferKind.Return
			|| decision.effect != OcamlControlEffect.ExitFunction
			|| decision.mechanism != OcamlControlTargetMechanism.RuntimeReturnSignal
			|| decision.runtimeCapabilityId != RETURN_SIGNAL_CAPABILITY_ID) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: control decision "${decision.id}" selects an unsupported transfer, effect, mechanism, or runtime capability';
		}
		final payload = decision.payload;
		if (!isAdmittedExactSide(payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.inputRepresentationId)
			|| payload.signalCarrierTypeId != "Obj.t"
			|| payload.outputSemanticTypeId != payload.inputSemanticTypeId
			|| payload.outputCarrierTypeId != payload.inputCarrierTypeId
			|| payload.outputRepresentationId != payload.inputRepresentationId
			|| payload.conversion != OcamlControlPayloadConversion.BoxAndRecoverExactValue
			|| payload.proofId != EXACT_VALUE_RETURN_PROOF_ID
			|| payload.proofClaim.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: control decision "${decision.id}" has an unsupported or incomplete exact-value payload crossing';
		}
		if (decision.profileEligibility.length != 2
			|| decision.profileEligibility[0] != "metal"
			|| decision.profileEligibility[1] != "portable"
			|| decision.reason.length == 0
			|| decision.proofId != EXACT_VALUE_RETURN_PROOF_ID
			|| decision.proofClaim.length == 0) {
			throw 'reflaxe.ocaml [ocaml-control:invalid-plan]: control decision "${decision.id}" has incomplete eligibility or proof metadata';
		}
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
			targetFunctionId: decision.targetFunctionId,
			payload: {
				inputSemanticTypeId: decision.payload.inputSemanticTypeId,
				inputCarrierTypeId: decision.payload.inputCarrierTypeId,
				inputRepresentationId: decision.payload.inputRepresentationId,
				signalCarrierTypeId: decision.payload.signalCarrierTypeId,
				outputSemanticTypeId: decision.payload.outputSemanticTypeId,
				outputCarrierTypeId: decision.payload.outputCarrierTypeId,
				outputRepresentationId: decision.payload.outputRepresentationId,
				conversion: decision.payload.conversion,
				proofId: decision.payload.proofId,
				proofClaim: decision.payload.proofClaim
			},
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

	static function requireBinding(decision:OcamlControlDecision, binding:OcamlFunctionPlanBinding):Void {
		if (decision.functionId != binding.functionId
			|| decision.targetFunctionId != binding.functionId
			|| decision.programRevision != binding.programRevision
			|| decision.bodyRevision != binding.bodyRevision
			|| decision.pipelineRevision != binding.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-control:stale-binding]: control decision "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
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

	static function expressionMatchesPayload(expression:TypedExpr, payload:OcamlControlPayloadPlan):Bool {
		return switch (payload.inputSemanticTypeId) {
			case "Int": OcamlRepresentationRegistry.isExactInt(expression.t);
			case "Bool": OcamlRepresentationRegistry.isExactBool(expression.t);
			case "String": OcamlRepresentationRegistry.isExactString(expression.t);
			case _: false;
		}
	}

	static function payloadFingerprint(payload:OcamlControlPayloadPlan):String {
		return [
			payload.inputSemanticTypeId,
			payload.inputCarrierTypeId,
			payload.inputRepresentationId,
			payload.signalCarrierTypeId,
			payload.outputSemanticTypeId,
			payload.outputCarrierTypeId,
			payload.outputRepresentationId,
			(payload.conversion : String),
			payload.proofId,
			payload.proofClaim
		].join("|");
	}

	static function decisionFingerprint(decision:OcamlControlDecision):String {
		return [
			decision.id,
			sourceKey(decision.source),
			(decision.kind : String),
			(decision.effect : String),
			decision.targetFunctionId,
			payloadFingerprint(decision.payload),
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
}

/**
	Selects the first exact-value early-return family from one final typed body.

	Only represented ordinary static Haxe methods with an identity-carrier
	`Int`, `Bool`, or `String` result are admitted. Direct root returns stay on
	the straight-line callable-result path; nested function literals own
	independent control boundaries and are deliberately skipped.
**/
class OcamlControlPlanner {
	final representations:OcamlRepresentationRegistry;
	final binding:OcamlFunctionPlanBinding;

	public function new(representations:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding) {
		this.representations = representations;
		this.binding = binding;
	}

	public function plan(body:Null<TypedExpr>, boundary:Null<OcamlCallableBoundaryPlan>):OcamlControlPlan {
		final boundaryPayload = admittedBoundaryPayload(boundary);
		if (boundaryPayload == null)
			return OcamlControlPlan.notAdmitted(binding);
		final decisions:Array<OcamlControlDecision> = [];
		var ordinal = 0;
		var supported = true;

		function visit(expression:TypedExpr, directRootStatement:Bool):Void {
			if (!supported)
				return;
			switch (expression.expr) {
				case TReturn(value):
					if (directRootStatement)
						return;
					final representation = value == null ? null : exactValueRepresentation(value);
					if (value == null
						|| representation == null
						|| representation.semanticTypeId != boundaryPayload.inputSemanticTypeId
						|| representation.carrierTypeId != boundaryPayload.inputCarrierTypeId
						|| representation.id != boundaryPayload.inputRepresentationId) {
						supported = false;
						return;
					}
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final id = "control:return:" + Sha256.encode(binding.functionId + "|" + ordinal++).substr(0, 24);
					final proofClaim = 'The final typed Haxe body assigns this return to the current ${representation.semanticTypeId} function. The selected private runtime signal boxes the exact ${representation.carrierTypeId} carrier only while control is in flight, and the matching function boundary recovers that same sealed carrier before it can cross the callable ABI.';
					decisions.push({
						id: id,
						source: source,
						kind: OcamlControlTransferKind.Return,
						effect: OcamlControlEffect.ExitFunction,
						targetFunctionId: binding.functionId,
						payload: {
							inputSemanticTypeId: representation.semanticTypeId,
							inputCarrierTypeId: representation.carrierTypeId,
							inputRepresentationId: representation.id,
							signalCarrierTypeId: "Obj.t",
							outputSemanticTypeId: representation.semanticTypeId,
							outputCarrierTypeId: representation.carrierTypeId,
							outputRepresentationId: representation.id,
							conversion: OcamlControlPayloadConversion.BoxAndRecoverExactValue,
							proofId: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID,
							proofClaim: proofClaim
						},
						mechanism: OcamlControlTargetMechanism.RuntimeReturnSignal,
						runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID,
						profileEligibility: ["metal", "portable"],
						reason: 'This return is nested below the function\'s direct result path, so it exits the current exact-${representation.semanticTypeId} Haxe function through one revision-bound private runtime signal.',
						proofId: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID,
						proofClaim: proofClaim,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					});
				case TFunction(_):
					// The nested function owns its own return target.
				case TBlock(expressions):
					for (child in expressions)
						visit(child, false);
				case _:
					TypedExprTools.iter(expression, child -> visit(child, false));
			}
		}

		if (body != null) {
			switch (body.expr) {
				case TBlock(expressions):
					for (expression in expressions)
						visit(expression, true);
				case _:
					visit(body, true);
			}
		}
		if (!supported)
			return OcamlControlPlan.notAdmitted(binding);
		return new OcamlControlPlan(true, binding, decisions);
	}

	function exactValueRepresentation(expression:TypedExpr):Null<OcamlRepresentationDecision> {
		if (OcamlRepresentationRegistry.isExactInt(expression.t))
			return representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactBool(expression.t))
			return representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactString(expression.t))
			return representations.selectExactString(OcamlRepresentationDomain.InternalValue);
		return null;
	}

	static function admittedBoundaryPayload(boundary:Null<OcamlCallableBoundaryPlan>):Null<OcamlCallValuePlan> {
		if (boundary == null
			|| boundary.kind != OcamlCallKind.DirectStaticHaxeMethod
			|| boundary.resultKind != OcamlCallResultKind.Value
			|| boundary.result == null) {
			return null;
		}
		final result = boundary.result;
		return result.inputSemanticTypeId == result.outputSemanticTypeId
			&& result.inputCarrierTypeId == result.outputCarrierTypeId
			&& result.inputRepresentationId == result.outputRepresentationId
			&& result.conversion == OcamlCallCarrierConversion.Identity
			&& OcamlControlPlan.isAdmittedExactSide(result.inputSemanticTypeId, result.inputCarrierTypeId,
				result.inputRepresentationId) ? OcamlCallPlan.copyValue(result) : null;
	}
}
#end
