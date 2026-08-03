import haxe.crypto.Sha256;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type.TVar;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.FunctionBodyRevision;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerPlan;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionContract;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionFamily;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionStatus;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchBranchResultPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchClauseDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchInputChannel;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchMatchPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchPrivateControlPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchUnmatchedPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlRuntimeTagPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlEnumDynamicCarrier;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry.OcamlSealedNestedFunctionPlan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlEnumRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

private typedef NestedReturnOnlyFixture = {
	final expression:TypedExpr;
	final externalLocals:Array<TVar>;
	final binding:OcamlFunctionPlanBinding;
	final plan:OcamlSealedNestedFunctionPlan;
}

/**
	Checks control-family independence, immutability, and fail-closed validation.

	The portable fixture proves behavior from a real typed Haxe program. This
	macro fixture deliberately corrupts return payloads, loop targets, and
	transfer records so an invalid family combination or stale body revision
	cannot reach OCaml syntax.
**/
class ControlPlanFixture {
	static inline final FUNCTION_ID = "Main|Main|static|function|value|generics:0|required:Int->Int";

	/** Builds one structurally valid occurrence ID for registry corruption tests. **/
	static function nestedOccurrenceId(label:String):String {
		return LexicalLocalIdentityPlan.FUNCTION_OCCURRENCE_ID_PREFIX + Sha256.encode(label);
	}

	/** Builds the exact nested binding that the registry will accept for a typed literal. **/
	static function nestedFunctionBinding(parent:OcamlFunctionPlanBinding, expression:TypedExpr, externalLocals:Array<TVar>,
			identities:LexicalLocalIdentityPlan):OcamlFunctionPlanBinding {
		final nestedFunction = switch (expression.expr) {
			case TFunction(tfunc): tfunc;
			case _: throw "The nested-function binding fixture requires a typed function literal";
		}
		final occurrence = identities.requireFunctionOccurrence(expression);
		return {
			functionId: OcamlFunctionPlanRegistry.nestedFunctionId(parent.functionId, occurrence.id),
			programRevision: parent.programRevision,
			bodyRevision: FunctionBodyRevision.initial(nestedFunction.expr, externalLocals).id,
			pipelineRevision: OcamlFunctionPlanRegistry.NESTED_FUNCTION_PIPELINE_REVISION
		};
	}

	static function binding(?bodyRevision:String = "body:control-fixture"):OcamlFunctionPlanBinding {
		return {
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: bodyRevision,
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function returnDecision(id:String, min:Int, ?targetId:String, ?conversion:OcamlControlPayloadConversion, ?mechanism:OcamlControlTargetMechanism,
			?semanticTypeId:String, ?outputSemanticTypeId:String, ?proofId:String, ?decisionBinding:OcamlFunctionPlanBinding,
			?decisionSource:OcamlLoweredSourceSpan):OcamlControlDecision {
		final selectedBinding = decisionBinding ?? binding();
		final target = targetId ?? selectedBinding.functionId;
		final selectedMechanism = mechanism ?? OcamlControlTargetMechanism.RuntimeReturnSignal;
		final semanticType = semanticTypeId ?? "Int";
		final outputSemanticType = outputSemanticTypeId ?? semanticType;
		final nullableCarrier = semanticType == "Null<Int>" || semanticType == "Null<Bool>";
		final dynamicCarrier = semanticType == "Dynamic";
		final selectedConversion = conversion ?? (nullableCarrier ? OcamlControlPayloadConversion.PreserveNullableCarrier : (dynamicCarrier ? OcamlControlPayloadConversion.PreserveDynamicReturnCarrier : OcamlControlPayloadConversion.BoxAndRecoverExactValue));
		final selectedProofId = proofId ?? switch (selectedConversion) {
			case PreserveNullableCarrier: OcamlControlPlan.NULLABLE_CARRIER_RETURN_PROOF_ID;
			case PreserveDynamicReturnCarrier: OcamlControlPlan.DYNAMIC_RETURN_PROOF_ID;
			case BoxExactIntToNullableCarrier: OcamlControlPlan.NULLABLE_INT_CONVERSION_RETURN_PROOF_ID;
			case BoxExactBoolToNullableCarrier: OcamlControlPlan.NULLABLE_BOOL_CONVERSION_RETURN_PROOF_ID;
			case _: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID;
		}
		final carrierType = switch (semanticType) {
			case "Int": "int";
			case "Bool": "bool";
			case "Null<Int>", "Null<Bool>", "Dynamic": "Obj.t";
			case "String": "string";
			case _: "unsupported";
		}
		final outputCarrierType = switch (outputSemanticType) {
			case "Int": "int";
			case "Bool": "bool";
			case "Null<Int>", "Null<Bool>", "Dynamic": "Obj.t";
			case "String": "string";
			case _: "unsupported";
		}
		final representationId = 'representation:$semanticType:internal-value';
		final outputRepresentationId = 'representation:$outputSemanticType:internal-value';
		final proof = 'fixture exact-$semanticType early-return crossing';
		return {
			id: id,
			source: decisionSource ?? {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: OcamlControlTransferKind.Return,
			effect: OcamlControlEffect.ExitFunction,
			targetKind: OcamlControlTargetKind.Function,
			targetId: target,
			payload: {
				inputSemanticTypeId: semanticType,
				inputCarrierTypeId: carrierType,
				inputRepresentationId: representationId,
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: outputSemanticType,
				outputCarrierTypeId: outputCarrierType,
				outputRepresentationId: outputRepresentationId,
				conversion: selectedConversion,
				proofId: selectedProofId,
				proofClaim: proof,
				nominalRepresentation: null
			},
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: selectedMechanism,
			runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: 'fixture nested return exits its owning exact-$semanticType function',
			proofId: selectedProofId,
			proofClaim: proof,
			functionId: selectedBinding.functionId,
			programRevision: selectedBinding.programRevision,
			bodyRevision: selectedBinding.bodyRevision,
			pipelineRevision: selectedBinding.pipelineRevision
		};
	}

	static function voidReturnDecision(id:String, min:Int, ?targetId:String, ?mechanism:OcamlControlTargetMechanism, ?runtimeCapabilityId:String,
			?proofId:String, ?payload:OcamlControlPayloadPlan):OcamlControlDecision {
		final proof = "fixture effect-only Void early-return crossing";
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: OcamlControlTransferKind.Return,
			effect: OcamlControlEffect.ExitFunction,
			targetKind: OcamlControlTargetKind.Function,
			targetId: targetId ?? FUNCTION_ID,
			payload: payload,
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: mechanism ?? OcamlControlTargetMechanism.RuntimeVoidReturnSignal,
			runtimeCapabilityId: runtimeCapabilityId ?? OcamlControlPlan.VOID_RETURN_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "fixture payloadless return exits its owning effect-only Void function",
			proofId: proofId ?? OcamlControlPlan.EFFECT_ONLY_VOID_RETURN_PROOF_ID,
			proofClaim: proof,
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function loopTarget(id:String, min:Int, ?kind:OcamlControlLoopKind, ?bodyRevision:String):OcamlControlLoopTarget {
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 20
			},
			kind: kind ?? OcamlControlLoopKind.While,
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: bodyRevision ?? "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33",
			proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
			proofClaim: "fixture lexical loop target"
		};
	}

	static function loopDecision(id:String, min:Int, targetId:String, kind:OcamlControlTransferKind, ?targetKind:OcamlControlTargetKind,
			?payload:OcamlControlPayloadPlan):OcamlControlDecision {
		final isBreak = kind == OcamlControlTransferKind.Break;
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: kind,
			effect: isBreak ? OcamlControlEffect.ExitLoop : OcamlControlEffect.NextLoopIteration,
			targetKind: targetKind ?? OcamlControlTargetKind.Loop,
			targetId: targetId,
			payload: payload,
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: isBreak ? OcamlControlTargetMechanism.RuntimeBreakSignal : OcamlControlTargetMechanism.RuntimeContinueSignal,
			runtimeCapabilityId: isBreak ? OcamlControlPlan.BREAK_SIGNAL_CAPABILITY_ID : OcamlControlPlan.CONTINUE_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "fixture lexical loop transfer",
			proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
			proofClaim: "fixture lexical loop transfer",
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function throwDecision(id:String, min:Int, semanticTypeId:String, ?conversion:OcamlControlPayloadConversion, ?runtimeTags:Array<String>,
			?targetId:String, ?targetKind:OcamlControlTargetKind, ?mechanism:OcamlControlTargetMechanism, ?outputSemanticTypeId:String,
			?runtimeTagPolicy:OcamlControlRuntimeTagPolicy, directEnum:Bool = false):OcamlControlDecision {
		final carrierTypeId = switch (semanticTypeId) {
			case "Int": "int";
			case "Bool": "bool";
			case "Null<Int>", "Null<Bool>", "Dynamic": "Obj.t";
			case "String": "string";
			case "Array<Int>": "int HxArray.t";
			case "Array<String>": "string HxArray.t";
			case "haxe.Exception": "Haxe_Exception.t";
			case "haxe.ValueException": "Haxe_ValueException.t";
			case _: directEnum ? OcamlEnumDynamicCarrier.CARRIER_MODEL + ":" + semanticTypeId : "unsupported";
		};
		final outputSemanticType = outputSemanticTypeId ?? semanticTypeId;
		final outputCarrierTypeId = switch (outputSemanticType) {
			case "Int": "int";
			case "Bool": "bool";
			case "Null<Int>", "Null<Bool>", "Dynamic": "Obj.t";
			case "String": "string";
			case "Array<Int>": "int HxArray.t";
			case "Array<String>": "string HxArray.t";
			case "haxe.Exception": "Haxe_Exception.t";
			case "haxe.ValueException": "Haxe_ValueException.t";
			case _: directEnum ? OcamlEnumDynamicCarrier.CARRIER_MODEL + ":" + outputSemanticType : "unsupported";
		};
		final representedArray = semanticTypeId == "Array<Int>" || semanticTypeId == "Array<String>";
		var selectedConversion = conversion ?? OcamlControlPlan.expectedThrowConversion(semanticTypeId, false, directEnum, representedArray);
		if (selectedConversion == null)
			selectedConversion = cast "unsupported";
		var selectedProofId = OcamlControlPlan.expectedThrowProofId(semanticTypeId, false, directEnum, representedArray);
		if (selectedProofId == null)
			selectedProofId = OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID;
		final representationId = switch (semanticTypeId) {
			case "Dynamic": OcamlControlPlan.DYNAMIC_CONTROL_REPRESENTATION_ID;
			case "haxe.Exception": OcamlControlPlan.HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID;
			case "haxe.ValueException": OcamlControlPlan.HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID;
			case _: directEnum ? OcamlControlPlan.enumThrowRepresentationId(semanticTypeId) : 'representation:$semanticTypeId:internal-value';
		}
		final outputRepresentationId = switch (outputSemanticType) {
			case "Dynamic": OcamlControlPlan.DYNAMIC_CONTROL_REPRESENTATION_ID;
			case "haxe.Exception": OcamlControlPlan.HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID;
			case "haxe.ValueException": OcamlControlPlan.HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID;
			case _: directEnum ? OcamlControlPlan.enumThrowRepresentationId(outputSemanticType) : 'representation:$outputSemanticType:internal-value';
		}
		final proof = 'fixture exact-$semanticTypeId Haxe exception crossing';
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: OcamlControlTransferKind.Throw,
			effect: OcamlControlEffect.RaiseHaxeValue,
			targetKind: targetKind ?? OcamlControlTargetKind.HaxeExceptionChannel,
			targetId: targetId ?? OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID,
			payload: {
				inputSemanticTypeId: semanticTypeId,
				inputCarrierTypeId: carrierTypeId,
				inputRepresentationId: representationId,
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: outputSemanticType,
				outputCarrierTypeId: outputCarrierTypeId,
				outputRepresentationId: outputRepresentationId,
				representationRevision: representedArray ? "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" : null,
				arrayDescriptorId: representedArray ? 'represented-array:$semanticTypeId' : null,
				arrayDescriptorRevision: representedArray ? "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" : null,
				conversion: selectedConversion,
				proofId: selectedProofId,
				proofClaim: proof,
				nominalRepresentation: null
			},
			runtimeTags: runtimeTags ?? OcamlControlPlan.expectedThrowTags(semanticTypeId, false, directEnum, representedArray),
			runtimeTagPolicy: runtimeTagPolicy ?? OcamlControlRuntimeTagPolicy.MergeDynamicWithExactRuntimeValue,
			mechanism: mechanism ?? OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal,
			runtimeCapabilityId: OcamlControlPlan.THROW_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: 'fixture exact-$semanticTypeId value enters the Haxe exception channel',
			proofId: selectedProofId,
			proofClaim: proof,
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function catchClause(id:String, min:Int, order:Int, variableName:String, semanticTypeId:String, ?runtimeTag:String,
			?conversion:OcamlCatchPayloadConversion, ?bodyResultPolicy:OcamlCatchBranchResultPolicy):OcamlCatchClauseDecision {
		final exact = semanticTypeId != "Dynamic";
		final carrier = switch (semanticTypeId) {
			case "Int": "int";
			case "Bool": "bool";
			case "String": "string";
			case "Dynamic": "Obj.t";
			case _: "unsupported";
		}
		final representation = semanticTypeId == "Dynamic" ? OcamlControlPlan.DYNAMIC_CONTROL_REPRESENTATION_ID : 'representation:$semanticTypeId:internal-value';
		final selectedConversion = conversion ?? switch (semanticTypeId) {
			case "Bool": OcamlCatchPayloadConversion.RecoverCheckedBool;
			case "Dynamic": OcamlCatchPayloadConversion.PreserveDynamicCarrier;
			case _: OcamlCatchPayloadConversion.RecoverExactValue;
		}
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			order: order,
			variableName: variableName,
			semanticTypeId: semanticTypeId,
			signalCarrierTypeId: "Obj.t",
			outputCarrierTypeId: carrier,
			outputRepresentationId: representation,
			matchPolicy: exact ? OcamlCatchMatchPolicy.ExactRuntimeTag : OcamlCatchMatchPolicy.MatchAll,
			runtimeTag: exact ? (runtimeTag ?? semanticTypeId) : runtimeTag,
			conversion: selectedConversion,
			nominalRepresentation: null,
			bodyResultPolicy: bodyResultPolicy ?? OcamlCatchBranchResultPolicy.PreserveTypedResult,
			effects: [
				OcamlCatchEffect.SelectFirstMatchingClause,
				OcamlCatchEffect.BindCatchVariable,
				OcamlCatchEffect.ExecuteCatchBody
			],
			proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
			proofClaim: 'fixture exact-$semanticTypeId catch clause',
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	/**
		Builds the dedicated control-only contract for Haxe exception wrappers.

		This intentionally does not claim that the program-wide representation
		model knows either class layout. The catch boundary only promises how an
		existing wrapper is preserved or a non-wrapper payload is wrapped once.
	**/
	static function haxeExceptionCatchClause(id:String, min:Int, order:Int, variableName:String, valueException:Bool):OcamlCatchClauseDecision {
		final semanticTypeId = valueException ? "haxe.ValueException" : "haxe.Exception";
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			order: order,
			variableName: variableName,
			semanticTypeId: semanticTypeId,
			signalCarrierTypeId: "Obj.t",
			outputCarrierTypeId: valueException ? "Haxe_ValueException.t" : "Haxe_Exception.t",
			outputRepresentationId: valueException ? OcamlControlPlan.HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID : OcamlControlPlan.HAXE_EXCEPTION_CONTROL_REPRESENTATION_ID,
			matchPolicy: valueException ? OcamlCatchMatchPolicy.MatchHaxeValueException : OcamlCatchMatchPolicy.MatchHaxeException,
			runtimeTag: null,
			conversion: valueException ? OcamlCatchPayloadConversion.PreserveOrWrapHaxeValueException : OcamlCatchPayloadConversion.PreserveOrWrapHaxeException,
			nominalRepresentation: null,
			bodyResultPolicy: OcamlCatchBranchResultPolicy.PreserveTypedResult,
			effects: [
				OcamlCatchEffect.SelectFirstMatchingClause,
				OcamlCatchEffect.BindCatchVariable,
				OcamlCatchEffect.ExecuteCatchBody
			],
			proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
			proofClaim: 'fixture $semanticTypeId catch-wrapper control contract',
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function catchChain(id:String, clauses:Array<OcamlCatchClauseDecision>, ?bodyRevision:String,
			?tryBodyResultPolicy:OcamlCatchBranchResultPolicy):OcamlCatchChainDecision {
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: 300,
				max: 380
			},
			clauses: clauses,
			tryBodyResultPolicy: tryBodyResultPolicy ?? OcamlCatchBranchResultPolicy.PreserveTypedResult,
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
			reason: "fixture exact primitive catch chain",
			proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
			proofClaim: "fixture exact primitive catch chain",
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: bodyRevision ?? "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function expectThrows(marker:String, operation:Void->Void):Void {
		try {
			operation();
		} catch (error:Dynamic) {
			final message = Std.string(error);
			if (message.indexOf(marker) < 0)
				throw 'Expected failure containing "$marker", got "$message"';
			return;
		}
		throw 'Expected failure containing "$marker"';
	}

	/** Returns the signature-ordered locals needed to fingerprint a fixture function literal. */
	static function nestedExternalLocals(expression:TypedExpr):Array<TVar> {
		return switch (expression.expr) {
			case TFunction(tfunc): tfunc.args.map(argument -> argument.v);
			case _: throw "The nested-function catalog fixture requires a typed function literal";
		}
	}

	/** Fingerprints the current body using the exact locals supplied to the nested catalog. */
	static function nestedBodyRevision(expression:TypedExpr, externalLocals:Array<TVar>):String {
		return switch (expression.expr) {
			case TFunction(tfunc): FunctionBodyRevision.initial(tfunc.expr, externalLocals).id;
			case _: throw "The nested-function catalog fixture requires a typed function literal";
		}
	}

	/** Returns one admitted exact carrier used on both sides of a fixture callable boundary. */
	static function nestedCallValue(index:Int, semanticTypeId:String = "Int"):OcamlCallValuePlan {
		final carrierTypeId = switch (semanticTypeId) {
			case "Int": "int";
			case "Bool": "bool";
			case _: throw 'The nested callable fixture does not support $semanticTypeId';
		}
		return {
			index: index,
			parameterOptional: false,
			inputSemanticTypeId: semanticTypeId,
			inputCarrierTypeId: carrierTypeId,
			inputRepresentationId: 'representation:$semanticTypeId:internal-value',
			outputSemanticTypeId: semanticTypeId,
			outputCarrierTypeId: carrierTypeId,
			outputRepresentationId: 'representation:$semanticTypeId:internal-value',
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: 'fixture exact $semanticTypeId carrier'
		};
	}

	/** Builds a valid represented function-value boundary for registry corruption tests. */
	static function nestedBoundary(planBinding:OcamlFunctionPlanBinding, resultSemanticTypeId:String = "Int"):OcamlCallableBoundaryPlan {
		final arguments = [nestedCallValue(0)];
		final result = nestedCallValue(-1, resultSemanticTypeId);
		final proofId = OcamlCallPlan.functionValueProofId(arguments, OcamlCallResultKind.Value, result);
		return {
			id: "callable:" + planBinding.functionId,
			calleeId: "function-value:" + planBinding.functionId,
			sourceModuleId: "",
			sourceTypeName: "",
			sourceFieldName: "",
			kind: OcamlCallKind.TypedFunctionValue,
			receiver: null,
			arguments: arguments,
			resultKind: OcamlCallResultKind.Value,
			result: result,
			profileEligibility: ["metal", "portable"],
			reason: 'fixture exact $resultSemanticTypeId nested function boundary',
			proofId: proofId,
			proofClaim: 'fixture exact $resultSemanticTypeId nested function boundary',
			functionId: planBinding.functionId,
			programRevision: planBinding.programRevision,
			bodyRevision: planBinding.bodyRevision,
			pipelineRevision: planBinding.pipelineRevision
		};
	}

	/** Finds the first early return owned by a fixture function body. */
	static function firstReturn(expression:TypedExpr):TypedExpr {
		var result:Null<TypedExpr> = null;
		function visit(current:TypedExpr):Void {
			if (result != null)
				return;
			switch (current.expr) {
				case TReturn(_):
					result = current;
				case TFunction(_):
				case _:
					TypedExprTools.iter(current, visit);
			}
		}
		visit(expression);
		if (result == null)
			throw "The admitted nested-function fixture requires an early return";
		return result;
	}

	/** Finds the first nested function literal inside a typed owner body. */
	static function firstFunctionLiteral(expression:TypedExpr):TypedExpr {
		var result:Null<TypedExpr> = null;
		function visit(current:TypedExpr):Void {
			if (result != null)
				return;
			switch (current.expr) {
				case TFunction(_):
					result = current;
				case _:
					TypedExprTools.iter(current, visit);
			}
		}
		visit(expression);
		if (result == null)
			throw "The fixture owner body contains no nested function literal";
		return result;
	}

	/** Returns nested function literals in the typed tree's structural order. */
	static function functionLiterals(expression:TypedExpr):Array<TypedExpr> {
		final result:Array<TypedExpr> = [];
		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TFunction(_):
					result.push(current);
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(expression);
		return result;
	}

	/** Builds one internally consistent return-only nested plan for ownership corruption tests. */
	static function nestedReturnOnlyFixture(parent:OcamlFunctionPlanBinding, expression:TypedExpr, identities:LexicalLocalIdentityPlan,
			decisionId:String):NestedReturnOnlyFixture {
		final nestedFunction = switch (expression.expr) {
			case TFunction(tfunc): tfunc;
			case _: throw "The return-only nested fixture requires a typed function literal";
		};
		final externalLocals = nestedExternalLocals(expression);
		final planBinding = nestedFunctionBinding(parent, expression, externalLocals, identities);
		final returned = firstReturn(nestedFunction.expr);
		final source = OcamlLoweredOrigin.sourceSpan(returned.pos);
		final decision = returnDecision(decisionId, source.min, planBinding.functionId, null, null, "Int", null, null, planBinding, source);
		final controls = new OcamlControlPlan(true, true, true, planBinding, [], [decision], [], [{expression: returned, decisionId: decision.id}], [], []);
		return {
			expression: expression,
			externalLocals: externalLocals,
			binding: planBinding,
			plan: {
				occurrenceId: identities.requireFunctionOccurrence(expression).id,
				parentBinding: parent,
				binding: planBinding,
				callableBoundary: nestedBoundary(planBinding),
				controls: controls,
				arrayLiteralProducers: new OcamlArrayLiteralProducerPlan([])
			}
		};
	}

	/** Finds the first `try` node so a legacy catch disposition can be indexed exactly. */
	static function firstTry(expression:TypedExpr):TypedExpr {
		var result:Null<TypedExpr> = null;
		function visit(current:TypedExpr):Void {
			if (result != null)
				return;
			switch (current.expr) {
				case TTry(_, _):
					result = current;
				case TFunction(_):
				case _:
					TypedExprTools.iter(current, visit);
			}
		}
		visit(expression);
		if (result == null)
			throw "The catch-exclusion fixture requires a typed try expression";
		return result;
	}

	public static macro function run():Expr {
		final first = returnDecision("control:return:first", 10);
		final second = returnDecision("control:return:second", 30);
		final loop = loopTarget("control-target:loop:first", 100);
		final loopBreak = loopDecision("control:break:first", 110, loop.id, OcamlControlTransferKind.Break);
		final loopContinue = loopDecision("control:continue:first", 120, loop.id, OcamlControlTransferKind.Continue);
		final forward = new OcamlControlPlan(true, true, false, binding(), [loop], [first, second, loopBreak, loopContinue]);
		final reverse = new OcamlControlPlan(true, true, false, binding(), [loop], [loopContinue, second, loopBreak, first]);
		if (forward.revision != reverse.revision)
			throw "Control-plan revision changed with input ordering";
		if (!forward.returnFamilyAdmitted
			|| !forward.loopFamilyAdmitted
			|| forward.throwFamilyAdmitted
			|| !forward.hasReturnTransfers()
			|| !forward.hasTransfersForTarget(loop.id)
			|| forward.loopTargets().length != 1
			|| forward.decisions().length != 4) {
			throw "Admitted control plan lost its sealed transfers";
		}
		if (forward.returnBoundaryDecision() == null)
			throw "Admitted control plan lost its return boundary";

		final copied = forward.decisions();
		copied[0].profileEligibility.push("corrupted");
		if (forward.decisions()[0].profileEligibility.length != 2)
			throw "Control decisions leaked mutable profile arrays";

		final empty = new OcamlControlPlan(true, true, true, binding(), [], []);
		if (!empty.returnFamilyAdmitted || !empty.loopFamilyAdmitted || !empty.throwFamilyAdmitted || empty.hasReturnTransfers()
			|| empty.returnBoundaryDecision() != null)
			throw "An admitted straight-line function did not retain independent empty families";
		expectThrows("control-admission:missing", () -> empty.admissionSnapshot());
		final loopOnly = new OcamlControlPlan(false, true, false, binding(), [loop], [loopBreak, loopContinue]);
		if (loopOnly.returnFamilyAdmitted
			|| !loopOnly.loopFamilyAdmitted
			|| loopOnly.throwFamilyAdmitted
			|| loopOnly.hasReturnTransfers())
			throw "Loop-family admission accidentally claimed the return family";
		final returnOnly = new OcamlControlPlan(true, false, false, binding(), [], [first, second]);
		if (!returnOnly.returnFamilyAdmitted || returnOnly.loopFamilyAdmitted || returnOnly.throwFamilyAdmitted || !returnOnly.hasReturnTransfers())
			throw "Return-family admission accidentally claimed the loop family";
		final intThrow = throwDecision("control:throw:int", 170, "Int");
		final throwOnly = new OcamlControlPlan(false, false, true, binding(), [], [intThrow]);
		if (throwOnly.returnFamilyAdmitted || throwOnly.loopFamilyAdmitted || !throwOnly.throwFamilyAdmitted || throwOnly.hasReturnTransfers()
			|| throwOnly.decisions().length != 1) {
			throw "Throw-family admission accidentally claimed or discarded another control family";
		}
		final intCatch = catchClause("control-catch-clause:int", 310, 0, "asInt", "Int");
		final boolCatch = catchClause("control-catch-clause:bool", 320, 1, "asBool", "Bool");
		final stringCatch = catchClause("control-catch-clause:string", 330, 2, "asString", "String");
		final dynamicCatch = catchClause("control-catch-clause:dynamic", 340, 3, "asDynamic", "Dynamic");
		final exactCatchChain = catchChain("control-catch-chain:exact", [intCatch, boolCatch, stringCatch, dynamicCatch]);
		final valueExceptionCatch = haxeExceptionCatchClause("control-catch-clause:value-exception", 350, 0, "asValueException", true);
		final exceptionCatch = haxeExceptionCatchClause("control-catch-clause:exception", 360, 1, "asException", false);
		final haxeExceptionCatchChain = catchChain("control-catch-chain:haxe-exception", [valueExceptionCatch, exceptionCatch]);
		final catchOnly = new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [exactCatchChain]);
		if (catchOnly.catchChains().length != 1 || catchOnly.catchChains()[0].clauses.length != 4)
			throw "Exact catch-chain admission lost its source-ordered clauses";
		final copiedCatchChains = catchOnly.catchChains();
		copiedCatchChains[0].clauses[0].effects.push(cast "corrupted");
		if (catchOnly.catchChains()[0].clauses[0].effects.length != 3)
			throw "Catch decisions leaked mutable clause effects";
		final legacy = OcamlControlPlan.notAdmitted(binding());
		if (legacy.returnFamilyAdmitted || legacy.loopFamilyAdmitted || legacy.throwFamilyAdmitted || legacy.hasReturnTransfers()
			|| legacy.catchChains().length != 0)
			throw "A legacy function became control-plan admitted";
		final blockedSource:OcamlLoweredSourceSpan = {file: "fixture/Main.hx", min: 400, max: 420};
		final returnBlocker = OcamlControlAdmissionContract.blocker("return-boundary-unrepresented", "control-admission:return:fixture", blockedSource,
			"anonymous{file:String,line:Int}");
		final catchBlocker = OcamlControlAdmissionContract.blocker("catch-clause-unrepresented", "control-admission:catch:fixture:clause:0", blockedSource,
			"Array<String>");
		final admission = OcamlControlAdmissionContract.create(binding(), [
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Return, 2, 0, false, [returnBlocker]),
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Loop, 0, 0, true, []),
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Throw, 1, 1, true, [])
		], [
			{
				occurrenceId: "control-catch-occurrence:fixture",
				source: blockedSource,
				status: OcamlControlAdmissionStatus.Blocked,
				chainId: null,
				blockers: [catchBlocker]
			}
		]);
		if (OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Return).status != OcamlControlAdmissionStatus.Blocked
			|| OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Loop).status != OcamlControlAdmissionStatus.NotNeeded
			|| admission.catches.length != 1) {
			throw "Control-admission snapshot did not distinguish blocked, admitted, and unused families";
		}
		final editedBlocker = OcamlControlAdmissionContract.copySnapshot(admission);
		Reflect.setField(cast editedBlocker.families[1].blockers[0], "message", "edited explanation");
		expectThrows("invalid-blocker", () -> OcamlControlAdmissionContract.requireSnapshot(editedBlocker));
		final missingFamily = OcamlControlAdmissionContract.copySnapshot(admission);
		missingFamily.families.pop();
		expectThrows("incomplete-families", () -> OcamlControlAdmissionContract.requireSnapshot(missingFamily));
		final staleAdmission = OcamlControlAdmissionContract.copySnapshot(admission);
		Reflect.setField(cast staleAdmission, "revision", "sha256:" + StringTools.rpad("", "0", 64));
		expectThrows("stale-revision", () -> OcamlControlAdmissionContract.requireSnapshot(staleAdmission));

		OcamlControlPlan.requireDecision(returnDecision("control:return:bool", 40, null, null, null, "Bool"));
		OcamlControlPlan.requireDecision(returnDecision("control:return:string", 45, null, null, null, "String"));
		final nullableIntReturn = returnDecision("control:return:nullable-int", 46, null, null, null, "Null<Int>");
		final nullableBoolReturn = returnDecision("control:return:nullable-bool", 47, null, null, null, "Null<Bool>");
		final dynamicReturn = returnDecision("control:return:dynamic", 47, null, null, null, "Dynamic");
		OcamlControlPlan.requireDecision(nullableIntReturn);
		OcamlControlPlan.requireDecision(nullableBoolReturn);
		OcamlControlPlan.requireDecision(dynamicReturn);
		if (dynamicReturn.payload == null || !OcamlControlPlan.isAdmittedDynamicReturnPayload(dynamicReturn.payload))
			throw "Exact Dynamic return lost its carrier-preserving function boundary";
		final nullableReturnOnly = new OcamlControlPlan(true, false, false, binding(), [], [nullableIntReturn]);
		if (nullableReturnOnly.returnBoundaryDecision()?.payload?.conversion != OcamlControlPayloadConversion.PreserveNullableCarrier)
			throw "Exact nullable return lost its carrier-preserving function boundary";
		final nullableIntConversion = returnDecision("control:return:int-to-nullable", 48, null, OcamlControlPayloadConversion.BoxExactIntToNullableCarrier,
			null, "Int", "Null<Int>");
		final nullableBoolConversion = returnDecision("control:return:bool-to-nullable", 49, null,
			OcamlControlPayloadConversion.BoxExactBoolToNullableCarrier, null, "Bool", "Null<Bool>");
		OcamlControlPlan.requireDecision(nullableIntConversion);
		OcamlControlPlan.requireDecision(nullableBoolConversion);
		final mixedNullableIntBoundary = new OcamlControlPlan(true, false, false, binding(), [], [nullableIntReturn, nullableIntConversion]);
		if (mixedNullableIntBoundary.returnBoundaryDecision()?.payload?.outputSemanticTypeId != "Null<Int>")
			throw "Compatible nullable identity and Int conversion lost their shared function boundary";
		final voidReturn = voidReturnDecision("control:return:void", 47);
		OcamlControlPlan.requireDecision(voidReturn);
		final voidReturnOnly = new OcamlControlPlan(true, false, false, binding(), [], [voidReturn]);
		if (voidReturnOnly.returnBoundaryDecision()?.mechanism != OcamlControlTargetMechanism.RuntimeVoidReturnSignal
			|| voidReturnOnly.returnBoundaryDecision()?.payload != null) {
			throw "Effect-only Void return lost its payloadless function boundary";
		}
		OcamlControlPlan.requireDecision(loopBreak);
		OcamlControlPlan.requireDecision(loopContinue);
		OcamlControlPlan.requireDecision(intThrow);
		OcamlControlPlan.requireDecision(throwDecision("control:throw:bool", 180, "Bool"));
		OcamlControlPlan.requireDecision(throwDecision("control:throw:string", 190, "String"));
		OcamlControlPlan.requireDecision(throwDecision("control:throw:nullable-int", 192, "Null<Int>"));
		OcamlControlPlan.requireDecision(throwDecision("control:throw:nullable-bool", 194, "Null<Bool>"));
		final arrayIntThrow = throwDecision("control:throw:array-int", 195, "Array<Int>");
		OcamlControlPlan.requireDecision(arrayIntThrow);
		if (arrayIntThrow.payload == null
			|| !OcamlControlPlan.isAdmittedRepresentedArrayThrowPayload(arrayIntThrow.payload)
			|| arrayIntThrow.runtimeTags.join(",") != "Dynamic,Array") {
			throw "The exact Array<Int> throw lost its sealed carrier, identity, or runtime tags";
		}
		final literalArrayThrow = throwDecision("control:throw:array-int-literal", 195, "Array<Int>");
		Reflect.setField(literalArrayThrow.payload, "arrayLiteralProducerId", "array-literal-producer:0123456789abcdef0123456789abcdef");
		Reflect.setField(literalArrayThrow.payload, "arrayLiteralProducerPlanRevision",
			"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc");
		OcamlControlPlan.requireDecision(literalArrayThrow);
		if (literalArrayThrow.payload == null || !OcamlControlPlan.isAdmittedRepresentedArrayThrowPayload(literalArrayThrow.payload))
			throw "The direct Array<Int> literal throw lost its paired producer identity and plan revision";
		final literalStringArrayThrow = throwDecision("control:throw:array-string-literal", 195, "Array<String>");
		Reflect.setField(literalStringArrayThrow.payload, "arrayLiteralProducerId", "array-literal-producer:fedcba9876543210fedcba9876543210");
		Reflect.setField(literalStringArrayThrow.payload, "arrayLiteralProducerPlanRevision",
			"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd");
		OcamlControlPlan.requireDecision(literalStringArrayThrow);
		if (literalStringArrayThrow.payload == null
			|| !OcamlControlPlan.isAdmittedRepresentedArrayThrowPayload(literalStringArrayThrow.payload)
			|| literalStringArrayThrow.runtimeTags.join(",") != "Dynamic,Array") {
			throw "The direct Array<String> literal throw lost its mandatory producer or represented-array tags";
		}
		OcamlControlPlan.requireDecision(throwDecision("control:throw:dynamic", 196, "Dynamic"));
		OcamlControlPlan.requireDecision(throwDecision("control:throw:haxe-exception", 197, "haxe.Exception"));
		OcamlControlPlan.requireDecision(throwDecision("control:throw:haxe-value-exception", 198, "haxe.ValueException"));
		final enumThrow = throwDecision("control:throw:enum", 199, "fixture.Signal", null, null, null, null, null, null, null, true);
		OcamlControlPlan.requireDecision(enumThrow);
		if (enumThrow.payload == null
			|| !OcamlControlPlan.isAdmittedEnumThrowPayload(enumThrow.payload)
			|| enumThrow.runtimeTags.join(",") != "Dynamic,fixture.Signal") {
			throw "The direct enum throw lost its sealed carrier or exact runtime tags";
		}
		final enumRuntimeLedger = new OcamlRuntimeRequirementLedger();
		enumRuntimeLedger.beginProgram(enumThrow.programRevision);
		OcamlEnumRuntimeRequirementRecorder.recordThrow(enumRuntimeLedger, enumThrow);
		final enumRequirements = enumRuntimeLedger.requirementsSorted();
		if (enumRequirements.length != 1
			|| enumRequirements[0].sourceId != enumThrow.id
			|| enumRequirements[0].subject.id != "fixture.Signal"
			|| enumRequirements[0].rootModules.join(",") != "HxEnum") {
			throw "The direct enum throw lost its exact source-to-HxEnum runtime requirement";
		}
		OcamlControlPlan.requireLoopTarget(loop);
		OcamlControlPlan.requireCatchChain(exactCatchChain);
		for (clause in exactCatchChain.clauses)
			OcamlControlPlan.requireCatchClause(clause);
		OcamlControlPlan.requireCatchChain(haxeExceptionCatchChain);
		for (clause in haxeExceptionCatchChain.clauses)
			OcamlControlPlan.requireCatchClause(clause);

		final missingId = returnDecision("", 50);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [missingId]));

		final staleReturnTarget = returnDecision("control:return:stale-target", 60, "Other|Other::value");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [staleReturnTarget]));

		final badConversion = returnDecision("control:return:bad-conversion", 70, null, cast "identity");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [badConversion]));

		final badMechanism = returnDecision("control:return:bad-mechanism", 80, null, null, cast "catch-all");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [badMechanism]));

		final unsupportedPayload = returnDecision("control:return:unsupported-payload", 85, null, null, null, "Float");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [unsupportedPayload]));

		final mismatchedPayload = returnDecision("control:return:mismatched-payload", 87, null, null, null, "Int", "Bool");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [mismatchedPayload]));
		final boxedNullablePayload = returnDecision("control:return:boxed-nullable", 88, null, OcamlControlPayloadConversion.BoxAndRecoverExactValue, null,
			"Null<Int>");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [boxedNullablePayload]));
		final wrongNullableProof = returnDecision("control:return:nullable-proof", 89, null, null, null, "Null<Bool>", null,
			OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [wrongNullableProof]));
		final mismatchedNullablePayload = returnDecision("control:return:mismatched-nullable", 90, null, null, null, "Null<Int>", "Int");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [mismatchedNullablePayload]));
		final boxedDynamicReturn = returnDecision("control:return:boxed-dynamic", 90, null, OcamlControlPayloadConversion.BoxAndRecoverExactValue, null,
			"Dynamic");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [boxedDynamicReturn]));
		final dynamicReturnWithWrongCarrier = returnDecision("control:return:dynamic-wrong-carrier", 90, null, null, null, "Dynamic");
		Reflect.setField(dynamicReturnWithWrongCarrier.payload, "inputCarrierTypeId", "int");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [dynamicReturnWithWrongCarrier]));
		final dynamicReturnWithWrongRepresentation = returnDecision("control:return:dynamic-wrong-representation", 90, null, null, null, "Dynamic");
		Reflect.setField(dynamicReturnWithWrongRepresentation.payload, "outputRepresentationId", "representation:Dynamic:other");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [dynamicReturnWithWrongRepresentation]));
		final foreignDynamicBinding = binding("body:foreign-dynamic-return");
		final dynamicReturnWithWrongBinding = returnDecision("control:return:dynamic-wrong-binding", 90, null, null, null, "Dynamic", null, null,
			foreignDynamicBinding);
		expectThrows("stale-binding", () -> new OcamlControlPlan(true, false, false, binding(), [], [dynamicReturnWithWrongBinding]));
		final wrongDirectionalConversion = returnDecision("control:return:wrong-directional-conversion", 91, null,
			OcamlControlPayloadConversion.BoxExactBoolToNullableCarrier, null, "Int", "Null<Int>");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [wrongDirectionalConversion]));
		final wrongDirectionalOutput = returnDecision("control:return:wrong-directional-output", 92, null,
			OcamlControlPayloadConversion.BoxExactIntToNullableCarrier, null, "Int", "Null<Bool>");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [wrongDirectionalOutput]));
		final wrongDirectionalProof = returnDecision("control:return:wrong-directional-proof", 93, null,
			OcamlControlPayloadConversion.BoxExactIntToNullableCarrier, null, "Int", "Null<Int>", OcamlControlPlan.NULLABLE_CARRIER_RETURN_PROOF_ID);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [wrongDirectionalProof]));
		final payloadBearingVoid = voidReturnDecision("control:return:void-payload", 88, null, null, null, null, first.payload);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [payloadBearingVoid]));
		final wrongVoidCapability = voidReturnDecision("control:return:void-capability", 89, null, null, OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [wrongVoidCapability]));
		final wrongVoidProof = voidReturnDecision("control:return:void-proof", 90, null, null, null, OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [wrongVoidProof]));
		final wrongVoidMechanism = voidReturnDecision("control:return:void-mechanism", 91, null, OcamlControlTargetMechanism.RuntimeReturnSignal);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [wrongVoidMechanism]));
		final mixedReturnBoundary = new OcamlControlPlan(true, false, false, binding(), [], [first, voidReturn]);
		expectThrows("conflicting-return-boundary", () -> mixedReturnBoundary.returnBoundaryDecision());
		final mixedCarrierBoundary = new OcamlControlPlan(true, false, false, binding(), [], [first, nullableIntReturn]);
		expectThrows("conflicting-return-boundary", () -> mixedCarrierBoundary.returnBoundaryDecision());
		final mixedNullableCarrierBoundary = new OcamlControlPlan(true, false, false, binding(), [], [nullableBoolReturn, nullableIntConversion]);
		expectThrows("conflicting-return-boundary", () -> mixedNullableCarrierBoundary.returnBoundaryDecision());

		final badThrowConversion = throwDecision("control:throw:bad-conversion", 200, "Int", cast "identity");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowConversion]));
		final badThrowTags = throwDecision("control:throw:bad-tags", 210, "Int", null, ["Int"]);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowTags]));
		final badThrowTagPolicy = throwDecision("control:throw:bad-tag-policy", 215, "Int", null, null, null, null, null, null,
			OcamlControlRuntimeTagPolicy.NoRuntimeTags);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowTagPolicy]));
		final badThrowTarget = throwDecision("control:throw:bad-target", 220, "Int", null, null, FUNCTION_ID, OcamlControlTargetKind.Function);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowTarget]));
		final badThrowMechanism = throwDecision("control:throw:bad-mechanism", 230, "Int", null, null, null, null, cast "catch-all");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowMechanism]));
		final unsupportedThrow = throwDecision("control:throw:unsupported", 240, "Float");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [unsupportedThrow]));
		final mismatchedThrow = throwDecision("control:throw:mismatched", 250, "Int", null, null, null, null, null, "Bool");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [mismatchedThrow]));
		final boxedNullableIntThrow = throwDecision("control:throw:boxed-nullable-int", 252, "Null<Int>",
			OcamlControlPayloadConversion.ReprAndRecoverExactValue);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [boxedNullableIntThrow]));
		final preservedNullableBoolThrow = throwDecision("control:throw:preserved-nullable-bool", 254, "Null<Bool>",
			OcamlControlPayloadConversion.PreserveNullableIntThrowCarrier);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [preservedNullableBoolThrow]));
		final boxedDynamicThrow = throwDecision("control:throw:boxed-dynamic", 255, "Dynamic", OcamlControlPayloadConversion.ReprAndRecoverExactValue);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [boxedDynamicThrow]));
		final arrayThrowWithWrongCarrier = throwDecision("control:throw:array-wrong-carrier", 255, "Array<Int>");
		Reflect.setField(arrayThrowWithWrongCarrier.payload, "inputCarrierTypeId", "Obj.t");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [arrayThrowWithWrongCarrier]));
		final arrayThrowWithWrongRepresentation = throwDecision("control:throw:array-wrong-representation", 255, "Array<Int>");
		Reflect.setField(arrayThrowWithWrongRepresentation.payload, "outputRepresentationId", "representation:Array<Int>:captured-local-storage");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [arrayThrowWithWrongRepresentation]));
		final arrayThrowWithWrongConversion = throwDecision("control:throw:array-wrong-conversion", 255, "Array<Int>",
			OcamlControlPayloadConversion.BoxNominalThrowCarrier);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [arrayThrowWithWrongConversion]));
		final arrayThrowWithWrongTags = throwDecision("control:throw:array-wrong-tags", 255, "Array<Int>", null, ["Dynamic"]);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [arrayThrowWithWrongTags]));
		final arrayThrowWithWrongProof = throwDecision("control:throw:array-wrong-proof", 255, "Array<Int>");
		Reflect.setField(arrayThrowWithWrongProof.payload, "proofId", OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [arrayThrowWithWrongProof]));
		final arrayThrowWithHalfProducer = throwDecision("control:throw:array-half-producer", 255, "Array<Int>");
		Reflect.setField(arrayThrowWithHalfProducer.payload, "arrayLiteralProducerId", "array-literal-producer:0123456789abcdef0123456789abcdef");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [arrayThrowWithHalfProducer]));
		final intThrowWithArrayProducer = throwDecision("control:throw:int-array-producer", 255, "Int");
		Reflect.setField(intThrowWithArrayProducer.payload, "arrayLiteralProducerId", "array-literal-producer:0123456789abcdef0123456789abcdef");
		Reflect.setField(intThrowWithArrayProducer.payload, "arrayLiteralProducerPlanRevision",
			"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [intThrowWithArrayProducer]));
		final stringArrayThrowWithoutProducer = throwDecision("control:throw:string-array-without-producer", 255, "Array<String>");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [stringArrayThrowWithoutProducer]));
		final stringArrayThrowWithHalfProducer = throwDecision("control:throw:string-array-half-producer", 255, "Array<String>");
		Reflect.setField(stringArrayThrowWithHalfProducer.payload, "arrayLiteralProducerId", "array-literal-producer:fedcba9876543210fedcba9876543210");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [stringArrayThrowWithHalfProducer]));
		final unsupportedBoolArrayThrow = throwDecision("control:throw:bool-array", 255, "Array<Bool>");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [unsupportedBoolArrayThrow]));
		final dynamicThrowWithProgramRepresentation = throwDecision("control:throw:dynamic-program-representation", 256, "Dynamic");
		if (dynamicThrowWithProgramRepresentation.payload == null)
			throw "The Dynamic representation-corruption fixture lost its payload";
		Reflect.setField(dynamicThrowWithProgramRepresentation.payload, "inputRepresentationId", "representation:Dynamic:internal-value");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [dynamicThrowWithProgramRepresentation]));
		final wrapperThrowWithProgramRepresentation = throwDecision("control:throw:wrapper-program-representation", 256, "haxe.ValueException");
		if (wrapperThrowWithProgramRepresentation.payload == null)
			throw "The Haxe exception-wrapper representation-corruption fixture lost its payload";
		Reflect.setField(wrapperThrowWithProgramRepresentation.payload, "inputRepresentationId", "representation:haxe.ValueException:internal-value");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [wrapperThrowWithProgramRepresentation]));
		final wrapperThrowWithNominalConversion = throwDecision("control:throw:wrapper-nominal-conversion", 256, "haxe.Exception",
			OcamlControlPayloadConversion.BoxNominalThrowCarrier);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [wrapperThrowWithNominalConversion]));
		final enumThrowWithWrongCarrier = throwDecision("control:throw:enum-wrong-carrier", 256, "fixture.Signal", null, null, null, null, null, null, null,
			true);
		Reflect.setField(enumThrowWithWrongCarrier.payload, "inputCarrierTypeId", OcamlEnumDynamicCarrier.CARRIER_MODEL + ":fixture.OtherSignal");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [enumThrowWithWrongCarrier]));
		final enumThrowWithWrongRepresentation = throwDecision("control:throw:enum-wrong-representation", 256, "fixture.Signal", null, null, null, null, null,
			null, null, true);
		Reflect.setField(enumThrowWithWrongRepresentation.payload, "inputRepresentationId", OcamlControlPlan.enumThrowRepresentationId("fixture.OtherSignal"));
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [enumThrowWithWrongRepresentation]));
		final enumThrowWithWrongTags = throwDecision("control:throw:enum-wrong-tags", 256, "fixture.Signal", null, ["Dynamic"], null, null, null, null, null,
			true);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [enumThrowWithWrongTags]));
		final enumThrowWithWrongProof = throwDecision("control:throw:enum-wrong-proof", 256, "fixture.Signal", null, null, null, null, null, null, null, true);
		Reflect.setField(enumThrowWithWrongProof.payload, "proofId", OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [enumThrowWithWrongProof]));
		final enumThrowFromOtherFunction = throwDecision("control:throw:enum-other-function", 256, "fixture.Signal", null, null, null, null, null, null, null,
			true);
		Reflect.setField(enumThrowFromOtherFunction, "functionId", "Other|Other|static|function|value|generics:0|required:Int->Int");
		expectThrows("stale-binding", () -> new OcamlControlPlan(false, false, true, binding(), [], [enumThrowFromOtherFunction]));
		final enumThrowFromOtherRevision = throwDecision("control:throw:enum-other-revision", 256, "fixture.Signal", null, null, null, null, null, null, null,
			true);
		Reflect.setField(enumThrowFromOtherRevision, "pipelineRevision", "typed-ocaml-function-plan-v32");
		expectThrows("stale-binding", () -> new OcamlControlPlan(false, false, true, binding(), [], [enumThrowFromOtherRevision]));
		final primitiveWithNominalProof = throwDecision("control:throw:primitive-with-nominal-proof", 257, "Int");
		final primitivePayload = primitiveWithNominalProof.payload;
		if (primitivePayload == null)
			throw "The primitive nominal-corruption fixture lost its payload";
		final fakeLayoutRevision = "sha256:" + StringTools.lpad("", "0", 64);
		Reflect.setField(primitivePayload, "nominalRepresentation", {
			targetModuleName: "Main",
			targetTypeName: "box_t",
			layoutRevision: fakeLayoutRevision,
			representationProofId: "whole-program-monomorphic-nominal-record-v1:" + fakeLayoutRevision
		});
		expectThrows("invalid proof", () -> new OcamlControlPlan(false, false, true, binding(), [], [primitiveWithNominalProof]));
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, false, binding(), [], [intThrow]));

		final badCatchOrder = catchChain("control-catch-chain:bad-order", [
			catchClause("control-catch-clause:bad-order:dynamic", 350, 0, "asDynamic", "Dynamic"),
			catchClause("control-catch-clause:bad-order:int", 360, 1, "asInt", "Int")
		]);
		expectThrows("invalid-catch-order", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [badCatchOrder]));
		final badCatchTag = catchChain("control-catch-chain:bad-tag", [catchClause("control-catch-clause:bad-tag", 350, 0, "asInt", "Int", "Bool")]);
		expectThrows("invalid-catch-clause", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [badCatchTag]));
		final badCatchConversion = catchChain("control-catch-chain:bad-conversion", [
			catchClause("control-catch-clause:bad-conversion", 350, 0, "asBool", "Bool", null, OcamlCatchPayloadConversion.RecoverExactValue)
		]);
		expectThrows("invalid-catch-clause", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [badCatchConversion]));
		final badCatchBodyResult = catchChain("control-catch-chain:bad-body-result", [
			catchClause("control-catch-clause:bad-body-result", 350, 0, "asInt", "Int", null, null, cast "infer-in-printer")
		]);
		expectThrows("invalid-catch-clause", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [badCatchBodyResult]));
		final badTryBodyResult = catchChain("control-catch-chain:bad-try-result", [intCatch], null, cast "infer-in-printer");
		expectThrows("invalid-catch-chain", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [badTryBodyResult]));
		final staleCatch = catchChain("control-catch-chain:stale", [intCatch], "body:other");
		expectThrows("stale-catch-clause", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [staleCatch]));
		final duplicateCatchClause = catchChain("control-catch-chain:duplicate-clause", [intCatch, intCatch]);
		expectThrows("duplicate-catch-clause", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [duplicateCatchClause]));
		final wrongValueExceptionConversion = haxeExceptionCatchClause("control-catch-clause:value-exception-wrong-conversion", 370, 0, "asValueException",
			true);
		Reflect.setField(wrongValueExceptionConversion, "conversion", OcamlCatchPayloadConversion.PreserveOrWrapHaxeException);
		expectThrows("invalid-catch-clause", () -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null, [
			catchChain("control-catch-chain:value-exception-wrong-conversion", [wrongValueExceptionConversion])
		]));
		final taggedExceptionCatch = haxeExceptionCatchClause("control-catch-clause:exception-with-tag", 380, 0, "asException", false);
		Reflect.setField(taggedExceptionCatch, "runtimeTag", "Exception");
		expectThrows("invalid-catch-clause",
			() -> new OcamlControlPlan(false, false, false, binding(), [], [], null, null,
				[catchChain("control-catch-chain:exception-with-tag", [taggedExceptionCatch])]));
		final exceptionFirstCatch = haxeExceptionCatchClause("control-catch-clause:exception-first", 390, 0, "asException", false);
		final laterIntCatch = catchClause("control-catch-clause:int-after-exception", 400, 1, "asInt", "Int");
		OcamlControlPlan.requireCatchChain(catchChain("control-catch-chain:exception-before-int", [exceptionFirstCatch, laterIntCatch]));

		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [first, loopBreak]));
		expectThrows("duplicate-decision", () -> new OcamlControlPlan(true, false, false, binding(), [], [first, first]));

		final sameSource = returnDecision("control:return:same-source", 10);
		expectThrows("duplicate-source-occurrence", () -> new OcamlControlPlan(true, false, false, binding(), [], [first, sameSource]));

		final typedLoop = Context.typeExpr(macro {
			while (true) {
				if (true)
					break;
				break;
			}
		});
		final typedLoops:Array<TypedExpr> = [];
		final typedBreaks:Array<TypedExpr> = [];
		function collectControlNodes(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TWhile(_, _, _):
					typedLoops.push(expression);
				case TBreak:
					typedBreaks.push(expression);
				case _:
			}
			TypedExprTools.iter(expression, collectControlNodes);
		}
		collectControlNodes(typedLoop);
		if (typedLoops.length != 1 || typedBreaks.length != 2)
			throw "The same-span occurrence fixture did not produce one loop and two break nodes";
		final sameSourceBreakA = loopDecision("control:break:same-source:a", 110, loop.id, OcamlControlTransferKind.Break);
		final sameSourceBreakB = loopDecision("control:break:same-source:b", 110, loop.id, OcamlControlTransferKind.Break);
		Reflect.setField(sameSourceBreakA, "source", OcamlLoweredOrigin.sourceSpan(typedBreaks[0].pos));
		Reflect.setField(sameSourceBreakB, "source", OcamlLoweredOrigin.sourceSpan(typedBreaks[1].pos));
		final indexedSameSource = new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA, sameSourceBreakB],
			[{expression: typedLoops[0], targetId: loop.id}], [
			{expression: typedBreaks[0], decisionId: sameSourceBreakA.id},
			{expression: typedBreaks[1], decisionId: sameSourceBreakB.id}
		]);
		if (indexedSameSource.decisionFor(typedBreaks[0])?.id != sameSourceBreakA.id
			|| indexedSameSource.decisionFor(typedBreaks[1])?.id != sameSourceBreakB.id) {
			throw "The typed occurrence index collapsed distinct same-span break nodes";
		}
		expectThrows("incomplete-occurrence-index",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [{expression: typedLoops[0], targetId: loop.id}], null));
		expectThrows("missing-target-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [],
				[{expression: typedBreaks[0], decisionId: sameSourceBreakA.id}]));
		expectThrows("missing-decision-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [{expression: typedLoops[0], targetId: loop.id}], []));
		expectThrows("duplicate-target-occurrence", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [
			{expression: typedLoops[0], targetId: loop.id},
			{expression: typedLoops[0], targetId: loop.id}
		], [{expression: typedBreaks[0], decisionId: sameSourceBreakA.id}]));
		expectThrows("duplicate-decision-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [{expression: typedLoops[0], targetId: loop.id}], [
				{expression: typedBreaks[0], decisionId: sameSourceBreakA.id},
				{expression: typedBreaks[0], decisionId: sameSourceBreakA.id}
			]));
		final ambiguousSourceBreakB = loopDecision("control:break:ambiguous-source:b", 110, loop.id, OcamlControlTransferKind.Break);
		Reflect.setField(ambiguousSourceBreakB, "source", OcamlLoweredOrigin.sourceSpan(typedBreaks[0].pos));
		expectThrows("ambiguous-decision-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA, ambiguousSourceBreakB], [
				{
					expression: typedLoops[0],
					targetId: loop.id
				}
			], [
				{expression: typedBreaks[0], decisionId: sameSourceBreakA.id},
				{expression: typedBreaks[0], decisionId: ambiguousSourceBreakB.id}
			]));

		final typedThrowsRoot = Context.typeExpr(macro {
			if (true)
				throw 1;
			throw 2;
		});
		final typedThrows:Array<TypedExpr> = [];
		function collectThrowNodes(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TThrow(_):
					typedThrows.push(expression);
				case _:
			}
			TypedExprTools.iter(expression, collectThrowNodes);
		}
		collectThrowNodes(typedThrowsRoot);
		if (typedThrows.length != 2)
			throw "The exact throw occurrence fixture did not produce two throw nodes";
		final sameSourceThrowA = throwDecision("control:throw:same-source:a", 260, "Int");
		final sameSourceThrowB = throwDecision("control:throw:same-source:b", 260, "Int");
		Reflect.setField(sameSourceThrowA, "source", OcamlLoweredOrigin.sourceSpan(typedThrows[0].pos));
		Reflect.setField(sameSourceThrowB, "source", OcamlLoweredOrigin.sourceSpan(typedThrows[1].pos));
		final indexedThrows = new OcamlControlPlan(false, false, true, binding(), [], [sameSourceThrowA, sameSourceThrowB], [], [
			{expression: typedThrows[0], decisionId: sameSourceThrowA.id},
			{expression: typedThrows[1], decisionId: sameSourceThrowB.id}
		]);
		if (indexedThrows.decisionFor(typedThrows[0])?.id != sameSourceThrowA.id
			|| indexedThrows.decisionFor(typedThrows[1])?.id != sameSourceThrowB.id) {
			throw "The typed occurrence index collapsed distinct same-span throw nodes";
		}

		final typedEnumThrowRoot = Context.typeExpr(macro throw haxe.io.Error.Blocked);
		final typedEnumThrows:Array<TypedExpr> = [];
		function collectEnumThrowNodes(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TThrow(_):
					typedEnumThrows.push(expression);
				case _:
			}
			TypedExprTools.iter(expression, collectEnumThrowNodes);
		}
		collectEnumThrowNodes(typedEnumThrowRoot);
		if (typedEnumThrows.length != 1)
			throw "The direct enum throw occurrence fixture did not produce one throw node";
		final sourceBoundEnumThrow = throwDecision("control:throw:enum-source-bound", 270, "haxe.io.Error", null, null, null, null, null, null, null, true);
		Reflect.setField(sourceBoundEnumThrow, "source", OcamlLoweredOrigin.sourceSpan(typedEnumThrows[0].pos));
		final indexedEnumThrow = new OcamlControlPlan(false, false, true, binding(), [], [sourceBoundEnumThrow], [],
			[{expression: typedEnumThrows[0], decisionId: sourceBoundEnumThrow.id}]);
		if (indexedEnumThrow.decisionFor(typedEnumThrows[0])?.id != sourceBoundEnumThrow.id)
			throw "The direct enum throw lost its exact source-bound typed occurrence";
		final wrongEnumThrow = throwDecision("control:throw:enum-wrong-type", 275, "fixture.Signal", null, null, null, null, null, null, null, true);
		Reflect.setField(wrongEnumThrow, "source", OcamlLoweredOrigin.sourceSpan(typedEnumThrows[0].pos));
		final wrongEnumPlan = new OcamlControlPlan(false, false, true, binding(), [], [wrongEnumThrow], [],
			[{expression: typedEnumThrows[0], decisionId: wrongEnumThrow.id}]);
		if (wrongEnumPlan.decisionFor(typedEnumThrows[0]) != null)
			throw "A direct enum throw accepted a sealed decision for another enum type";
		final wrongSourceEnumThrow = throwDecision("control:throw:enum-wrong-source", 280, "haxe.io.Error", null, null, null, null, null, null, null, true);
		final actualEnumSource = OcamlLoweredOrigin.sourceSpan(typedEnumThrows[0].pos);
		Reflect.setField(wrongSourceEnumThrow, "source", {
			file: actualEnumSource.file,
			min: actualEnumSource.min + 1,
			max: actualEnumSource.max + 1
		});
		expectThrows("stale-decision-source",
			() -> new OcamlControlPlan(false, false, true, binding(), [], [wrongSourceEnumThrow], [],
				[{expression: typedEnumThrows[0], decisionId: wrongSourceEnumThrow.id}]));

		final typedCatchRoot = Context.typeExpr(macro try {
			throw true;
		} catch (asInt:Int) {
			Sys.println(Std.string(asInt));
		} catch (asBool:Bool) {
			Sys.println(Std.string(asBool));
		} catch (asString:String) {
			Sys.println(Std.string(asString));
		} catch (asDynamic:Dynamic) {
			Sys.println(Std.string(asDynamic));
		});
		final typedTries:Array<TypedExpr> = [];
		function collectTryNodes(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TTry(_, _):
					typedTries.push(expression);
				case _:
			}
			TypedExprTools.iter(expression, collectTryNodes);
		}
		collectTryNodes(typedCatchRoot);
		if (typedTries.length != 1)
			throw "The exact catch occurrence fixture did not produce one typed try";
		final typedCatchSource:OcamlLoweredSourceSpan = {
			file: "test/oracle/control/Main.hx",
			min: 300,
			max: 380
		};
		final indexedCatch = new OcamlControlPlan(false, false, false, binding(), [], [], [], [], [exactCatchChain], [
			{
				expression: typedTries[0],
				occurrenceId: "control-catch-occurrence:exact",
				source: typedCatchSource,
				chainId: exactCatchChain.id
			}
		]);
		if (!indexedCatch.hasCatchDispositionFor(typedTries[0]) || indexedCatch.catchChainFor(typedTries[0])?.id != exactCatchChain.id)
			throw "The typed catch occurrence did not resolve its exact source-ordered chain";
		final indexedLegacyCatch = new OcamlControlPlan(false, false, false, binding(), [], [], [], [], [], [
			{
				expression: typedTries[0],
				occurrenceId: "control-catch-occurrence:legacy",
				source: typedCatchSource,
				chainId: null
			}
		]);
		if (!indexedLegacyCatch.hasCatchDispositionFor(typedTries[0]) || indexedLegacyCatch.catchChainFor(typedTries[0]) != null)
			throw "An explicit legacy catch disposition became an admitted chain";
		expectThrows("missing-catch-occurrence", () -> new OcamlControlPlan(false, false, false, binding(), [], [], [], [], [exactCatchChain], [
			{
				expression: typedTries[0],
				occurrenceId: "control-catch-occurrence:legacy-only",
				source: typedCatchSource,
				chainId: null
			}
		]));
		expectThrows("duplicate-catch-occurrence", () -> new OcamlControlPlan(false, false, false, binding(), [], [], [], [], [exactCatchChain], [
			{
				expression: typedTries[0],
				occurrenceId: "control-catch-occurrence:duplicate",
				source: typedCatchSource,
				chainId: exactCatchChain.id
			},
			{
				expression: typedTries[0],
				occurrenceId: "control-catch-occurrence:duplicate",
				source: typedCatchSource,
				chainId: exactCatchChain.id
			}
		]));
		expectThrows("missing-catch-occurrence", () -> new OcamlControlPlan(false, false, false, binding(), [], [], [], [], [], [
			{
				expression: typedTries[0],
				occurrenceId: "control-catch-occurrence:missing-chain",
				source: typedCatchSource,
				chainId: "control-catch-chain:missing"
			}
		]));

		expectThrows("missing-target", () -> new OcamlControlPlan(false, true, false, binding(), [], [loopBreak]));
		final wrongTargetKind = loopDecision("control:break:wrong-kind", 130, loop.id, OcamlControlTransferKind.Break, OcamlControlTargetKind.Function);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [wrongTargetKind]));
		final payloadBearingLoop = loopDecision("control:break:payload", 140, loop.id, OcamlControlTransferKind.Break, null, first.payload);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [payloadBearingLoop]));
		final staleLoop = loopTarget("control-target:loop:stale", 150, null, "body:other");
		expectThrows("stale-target", () -> new OcamlControlPlan(false, true, false, binding(), [staleLoop], []));
		final duplicateLoop = loopTarget(loop.id, 160);
		expectThrows("duplicate-target", () -> new OcamlControlPlan(false, true, false, binding(), [loop, duplicateLoop], []));
		final sameLoopSource = loopTarget("control-target:loop:same-source", 100);
		expectThrows("duplicate-target-source", () -> new OcamlControlPlan(false, true, false, binding(), [loop, sameLoopSource], []));

		expectThrows("stale-plan", () -> forward.requirePlanBinding(binding("body:other")));

		final nestedRegistry = new OcamlFunctionPlanRegistry();
		nestedRegistry.beginProgram("program:nested-catalog-fixture");
		final nestedParent:OcamlFunctionPlanBinding = {
			functionId: "Main|Main|static|function|nestedOwner|generics:0|->Int",
			programRevision: "program:nested-catalog-fixture",
			bodyRevision: "0:nested-parent-body",
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
		final otherParent:OcamlFunctionPlanBinding = {
			functionId: "Main|Main|static|function|otherOwner|generics:0|->Int",
			programRevision: nestedParent.programRevision,
			bodyRevision: nestedParent.bodyRevision,
			pipelineRevision: nestedParent.pipelineRevision
		};
		final nestedExpression = Context.typeExpr(macro function(flag:Bool):Int {
			if (flag)
				return 6;
			return 0;
		});
		final missingExpression = Context.typeExpr(macro function(flag:Bool):Int {
			return flag ? 1 : 0;
		});
		final nestedExternalLocalList = nestedExternalLocals(nestedExpression);
		final nestedObservedBodyRevision = nestedBodyRevision(nestedExpression, nestedExternalLocalList);
		nestedRegistry.deferNestedFunction(nestedExpression, nestedParent, nestedExternalLocalList, nestedObservedBodyRevision,
			"fixture explicitly defers one observed literal");
		if (nestedRegistry.nestedFunctionPlanFor(nestedExpression, nestedParent) != null)
			throw "An explicitly deferred nested function unexpectedly returned an admitted plan";
		expectThrows("duplicate-occurrence",
			() -> nestedRegistry.deferNestedFunction(nestedExpression, nestedParent, nestedExternalLocalList, nestedObservedBodyRevision, "fixture duplicate"));
		expectThrows("unobserved-occurrence", () -> nestedRegistry.nestedFunctionPlanFor(missingExpression, nestedParent));
		expectThrows("parent-mismatch", () -> nestedRegistry.nestedFunctionPlanFor(nestedExpression, otherParent));
		final staleParent:OcamlFunctionPlanBinding = {
			functionId: nestedParent.functionId,
			programRevision: "program:stale",
			bodyRevision: nestedParent.bodyRevision,
			pipelineRevision: nestedParent.pipelineRevision
		};
		expectThrows("stale-parent", () -> nestedRegistry.nestedFunctionPlanFor(nestedExpression, staleParent));

		final admittedOwnerBody = Context.typeExpr(macro {
			final local = function(value:Int):Int {
				if (value > 0)
					return 6;
				return 0;
			};
			local(1);
		});
		final admittedExpression = firstFunctionLiteral(admittedOwnerBody);
		final admittedFunction = switch (admittedExpression.expr) {
			case TFunction(tfunc): tfunc;
			case _: throw "The admitted nested-function fixture did not type as a function literal";
		};
		final admittedExternalLocals = nestedExternalLocals(admittedExpression);
		final admittedIdentities = LexicalLocalIdentityPlan.build(nestedParent.functionId, admittedOwnerBody);
		nestedRegistry.registerRootIdentityPlan(nestedParent, admittedIdentities);
		final admittedOccurrence = admittedIdentities.requireFunctionOccurrence(admittedExpression);
		final admittedBinding = nestedFunctionBinding(nestedParent, admittedExpression, admittedExternalLocals, admittedIdentities);
		final admittedReturn = firstReturn(admittedFunction.expr);
		final admittedReturnSource = OcamlLoweredOrigin.sourceSpan(admittedReturn.pos);
		final admittedDecision = returnDecision("control:return:nested-admitted", admittedReturnSource.min, admittedBinding.functionId, null, null, "Int",
			null, null, admittedBinding, admittedReturnSource);
		final admittedControls = new OcamlControlPlan(true, true, true, admittedBinding, [], [admittedDecision], [],
			[{expression: admittedReturn, decisionId: admittedDecision.id}], [], []);
		final noArrayLiteralProducers = new OcamlArrayLiteralProducerPlan([]);
		final admittedPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: admittedOccurrence.id,
			parentBinding: nestedParent,
			binding: admittedBinding,
			callableBoundary: nestedBoundary(admittedBinding),
			controls: admittedControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		final noncanonicalIdentities = LexicalLocalIdentityPlan.build(nestedParent.functionId, admittedExpression);
		final noncanonicalOccurrence = noncanonicalIdentities.requireFunctionOccurrence(admittedExpression);
		if (noncanonicalOccurrence.id == admittedOccurrence.id)
			throw "The noncanonical identity fixture did not move the literal to a different structural path";
		final noncanonicalBinding = nestedFunctionBinding(nestedParent, admittedExpression, admittedExternalLocals, noncanonicalIdentities);
		final noncanonicalDecision = returnDecision("control:return:nested-noncanonical", admittedReturnSource.min, noncanonicalBinding.functionId, null,
			null, "Int", null, null, noncanonicalBinding, admittedReturnSource);
		final noncanonicalControls = new OcamlControlPlan(true, true, true, noncanonicalBinding, [], [noncanonicalDecision], [],
			[{expression: admittedReturn, decisionId: noncanonicalDecision.id}], [], []);
		final noncanonicalPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: noncanonicalOccurrence.id,
			parentBinding: nestedParent,
			binding: noncanonicalBinding,
			callableBoundary: nestedBoundary(noncanonicalBinding),
			controls: noncanonicalControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("foreign-root-identities",
			() -> nestedRegistry.sealNestedFunction(admittedExpression, admittedExternalLocals, noncanonicalBinding.bodyRevision, noncanonicalPlan,
				noncanonicalIdentities));
		final wrongNestedBinding:OcamlFunctionPlanBinding = {
			functionId: nestedParent.functionId + "|nested-function|plausible-but-wrong",
			programRevision: admittedBinding.programRevision,
			bodyRevision: admittedBinding.bodyRevision,
			pipelineRevision: admittedBinding.pipelineRevision
		};
		final wrongNestedBindingPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: admittedOccurrence.id,
			parentBinding: nestedParent,
			binding: wrongNestedBinding,
			callableBoundary: admittedPlan.callableBoundary,
			controls: admittedPlan.controls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("binding-mismatch",
			() -> nestedRegistry.sealNestedFunction(admittedExpression, admittedExternalLocals, admittedBinding.bodyRevision, wrongNestedBindingPlan,
				admittedIdentities));
		final staleRootParent:OcamlFunctionPlanBinding = {
			functionId: nestedParent.functionId,
			programRevision: nestedParent.programRevision,
			bodyRevision: "0:stale-root-body",
			pipelineRevision: nestedParent.pipelineRevision
		};
		final staleRootPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: admittedPlan.occurrenceId,
			parentBinding: staleRootParent,
			binding: admittedPlan.binding,
			callableBoundary: admittedPlan.callableBoundary,
			controls: admittedPlan.controls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("stale-root-binding",
			() -> nestedRegistry.sealNestedFunction(admittedExpression, admittedExternalLocals, admittedBinding.bodyRevision, staleRootPlan,
				admittedIdentities));
		expectThrows("conflicting-root-binding", () -> nestedRegistry.registerRootIdentityPlan(staleRootParent, admittedIdentities));
		nestedRegistry.sealNestedFunction(admittedExpression, admittedExternalLocals, admittedBinding.bodyRevision, admittedPlan, admittedIdentities);
		final sealedAdmittedPlan = nestedRegistry.nestedFunctionPlanFor(admittedExpression, nestedParent);
		if (sealedAdmittedPlan == null)
			throw "An admitted nested function did not return its sealed plan";
		if (sealedAdmittedPlan.arrayLiteralProducers.decisions().length != 0)
			throw "A nested function without array literals did not preserve its explicit empty producer plan";
		final malformedOccurrenceExpression = Context.typeExpr(macro function(value:Int):Int {
			if (value > 0)
				return 6;
			return 0;
		});
		final malformedOccurrenceIdentities = LexicalLocalIdentityPlan.build(nestedParent.functionId, malformedOccurrenceExpression);
		final malformedOccurrencePlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: "nested-function-occurrence:not-a-generic-identity",
			parentBinding: admittedPlan.parentBinding,
			binding: admittedPlan.binding,
			callableBoundary: admittedPlan.callableBoundary,
			controls: admittedPlan.controls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("missing-identity",
			() -> nestedRegistry.sealNestedFunction(malformedOccurrenceExpression, nestedExternalLocals(malformedOccurrenceExpression),
				admittedBinding.bodyRevision, malformedOccurrencePlan, malformedOccurrenceIdentities));
		final foreignOccurrencePlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: nestedOccurrenceId("valid-but-foreign"),
			parentBinding: admittedPlan.parentBinding,
			binding: admittedPlan.binding,
			callableBoundary: admittedPlan.callableBoundary,
			controls: admittedPlan.controls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("foreign-occurrence",
			() -> nestedRegistry.sealNestedFunction(malformedOccurrenceExpression, nestedExternalLocals(malformedOccurrenceExpression),
				admittedBinding.bodyRevision, foreignOccurrencePlan, admittedIdentities));
		final crossRootOwnerId = "Main|Main|static|function|crossRootOwner|generics:0|->Int";
		final ordinaryImpostorParent:OcamlFunctionPlanBinding = {
			functionId: crossRootOwnerId + "|nested-function|ordinary-impostor",
			programRevision: nestedParent.programRevision,
			bodyRevision: nestedParent.bodyRevision,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
		final ordinaryImpostorBinding:OcamlFunctionPlanBinding = {
			functionId: OcamlFunctionPlanRegistry.nestedFunctionId(ordinaryImpostorParent.functionId,
				malformedOccurrenceIdentities.requireFunctionOccurrence(malformedOccurrenceExpression).id),
			programRevision: admittedBinding.programRevision,
			bodyRevision: admittedBinding.bodyRevision,
			pipelineRevision: admittedBinding.pipelineRevision
		};
		final ordinaryImpostorPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: malformedOccurrenceIdentities.requireFunctionOccurrence(malformedOccurrenceExpression).id,
			parentBinding: ordinaryImpostorParent,
			binding: ordinaryImpostorBinding,
			callableBoundary: admittedPlan.callableBoundary,
			controls: admittedPlan.controls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("foreign-root-identities",
			() -> nestedRegistry.sealNestedFunction(malformedOccurrenceExpression, nestedExternalLocals(malformedOccurrenceExpression),
				admittedBinding.bodyRevision, ordinaryImpostorPlan, malformedOccurrenceIdentities));

		// A function ID is text, so an ordinary function can legitimately contain
		// the nested-function separator in its own name. Register a child below that
		// root, then prove a second root cannot claim a deeper child merely because
		// its shorter ID is a textual prefix of the registered parent's ID.
		final impostorRootExpression = Context.typeExpr(macro function(value:Int):Int {
			if (value > 0)
				return 9;
			return 0;
		});
		final impostorRootFunction = switch (impostorRootExpression.expr) {
			case TFunction(tfunc): tfunc;
			case _: throw "The impostor-root fixture did not type as a function literal";
		};
		final impostorRootExternalLocals = nestedExternalLocals(impostorRootExpression);
		final impostorRootIdentities = LexicalLocalIdentityPlan.build(ordinaryImpostorParent.functionId, impostorRootExpression);
		nestedRegistry.registerRootIdentityPlan(ordinaryImpostorParent, impostorRootIdentities);
		final impostorRootBinding = nestedFunctionBinding(ordinaryImpostorParent, impostorRootExpression, impostorRootExternalLocals, impostorRootIdentities);
		final impostorRootReturn = firstReturn(impostorRootFunction.expr);
		final impostorRootReturnSource = OcamlLoweredOrigin.sourceSpan(impostorRootReturn.pos);
		final impostorRootDecision = returnDecision("control:return:nested-impostor-root", impostorRootReturnSource.min, impostorRootBinding.functionId, null,
			null, "Int", null, null, impostorRootBinding, impostorRootReturnSource);
		final impostorRootControls = new OcamlControlPlan(true, true, true, impostorRootBinding, [], [impostorRootDecision], [],
			[{expression: impostorRootReturn, decisionId: impostorRootDecision.id}], [], []);
		final impostorRootPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: impostorRootIdentities.requireFunctionOccurrence(impostorRootExpression).id,
			parentBinding: ordinaryImpostorParent,
			binding: impostorRootBinding,
			callableBoundary: nestedBoundary(impostorRootBinding),
			controls: impostorRootControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		nestedRegistry.sealNestedFunction(impostorRootExpression, impostorRootExternalLocals, impostorRootBinding.bodyRevision, impostorRootPlan,
			impostorRootIdentities);

		final crossRootChildExpression = Context.typeExpr(macro function(value:Int):Int {
			if (value > 0)
				return 10;
			return 0;
		});
		final crossRootChildFunction = switch (crossRootChildExpression.expr) {
			case TFunction(tfunc): tfunc;
			case _: throw "The cross-root child fixture did not type as a function literal";
		};
		final crossRootChildExternalLocals = nestedExternalLocals(crossRootChildExpression);
		final crossRootChildIdentities = LexicalLocalIdentityPlan.build(crossRootOwnerId, crossRootChildExpression);
		final crossRootOwnerBinding:OcamlFunctionPlanBinding = {
			functionId: crossRootOwnerId,
			programRevision: nestedParent.programRevision,
			bodyRevision: nestedParent.bodyRevision,
			pipelineRevision: nestedParent.pipelineRevision
		};
		nestedRegistry.registerRootIdentityPlan(crossRootOwnerBinding, crossRootChildIdentities);
		final crossRootChildBinding = nestedFunctionBinding(impostorRootBinding, crossRootChildExpression, crossRootChildExternalLocals,
			crossRootChildIdentities);
		final crossRootChildReturn = firstReturn(crossRootChildFunction.expr);
		final crossRootChildReturnSource = OcamlLoweredOrigin.sourceSpan(crossRootChildReturn.pos);
		final crossRootChildDecision = returnDecision("control:return:nested-cross-root", crossRootChildReturnSource.min, crossRootChildBinding.functionId,
			null, null, "Int", null, null, crossRootChildBinding, crossRootChildReturnSource);
		final crossRootChildControls = new OcamlControlPlan(true, true, true, crossRootChildBinding, [], [crossRootChildDecision], [],
			[{expression: crossRootChildReturn, decisionId: crossRootChildDecision.id}], [], []);
		final crossRootChildPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: crossRootChildIdentities.requireFunctionOccurrence(crossRootChildExpression).id,
			parentBinding: impostorRootBinding,
			binding: crossRootChildBinding,
			callableBoundary: nestedBoundary(crossRootChildBinding),
			controls: crossRootChildControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("foreign-parent-occurrence",
			() -> nestedRegistry.sealNestedFunction(crossRootChildExpression, crossRootChildExternalLocals, crossRootChildBinding.bodyRevision,
				crossRootChildPlan, crossRootChildIdentities));

		final siblingRegistry = new OcamlFunctionPlanRegistry();
		siblingRegistry.beginProgram("program:same-root-parent-fixture");
		final siblingRoot:OcamlFunctionPlanBinding = {
			functionId: "Main|Main|static|function|siblingRoot|generics:0|->Int",
			programRevision: "program:same-root-parent-fixture",
			bodyRevision: "0:sibling-root-body",
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
		final siblingOwnerBody = Context.typeExpr(macro {
			final siblingA = function(value:Int):Int {
				if (value > 0)
					return 1;
				return 0;
			};
			final siblingB = function(value:Int):Int {
				final child = function(childValue:Int):Int {
					if (childValue > 0)
						return 2;
					return 0;
				};
				if (value > 0)
					return child(value);
				return 0;
			};
			siblingA(1) + siblingB(1);
		});
		final siblingExpressions = functionLiterals(siblingOwnerBody);
		if (siblingExpressions.length != 3)
			throw 'The same-root parent fixture expected three function literals, got ${siblingExpressions.length}';
		final siblingIdentities = LexicalLocalIdentityPlan.build(siblingRoot.functionId, siblingOwnerBody);
		siblingRegistry.registerRootIdentityPlan(siblingRoot, siblingIdentities);
		final siblingA = nestedReturnOnlyFixture(siblingRoot, siblingExpressions[0], siblingIdentities, "control:return:sibling-a");
		final siblingB = nestedReturnOnlyFixture(siblingRoot, siblingExpressions[1], siblingIdentities, "control:return:sibling-b");
		siblingRegistry.sealNestedFunction(siblingA.expression, siblingA.externalLocals, siblingA.binding.bodyRevision, siblingA.plan, siblingIdentities);
		siblingRegistry.sealNestedFunction(siblingB.expression, siblingB.externalLocals, siblingB.binding.bodyRevision, siblingB.plan, siblingIdentities);
		final wrongSiblingChild = nestedReturnOnlyFixture(siblingA.binding, siblingExpressions[2], siblingIdentities, "control:return:wrong-sibling-child");
		expectThrows("foreign-parent-occurrence",
			() -> siblingRegistry.sealNestedFunction(wrongSiblingChild.expression, wrongSiblingChild.externalLocals, wrongSiblingChild.binding.bodyRevision,
				wrongSiblingChild.plan, siblingIdentities));
		final siblingChild = nestedReturnOnlyFixture(siblingB.binding, siblingExpressions[2], siblingIdentities, "control:return:sibling-child");
		siblingRegistry.sealNestedFunction(siblingChild.expression, siblingChild.externalLocals, siblingChild.binding.bodyRevision, siblingChild.plan,
			siblingIdentities);
		if (siblingRegistry.nestedFunctionPlanFor(siblingChild.expression, siblingB.binding) == null)
			throw "The exact same-root nested parent did not retain its child plan";

		// Starting another request with the same program name must still discard all
		// request-local identity and parent records. Re-registering a freshly built
		// lookup and sealing the same literals proves the old expression, occurrence,
		// nested-parent, and root records cannot authorize the new request.
		siblingRegistry.beginProgram(siblingRoot.programRevision);
		expectThrows("stale-parent", () -> siblingRegistry.nestedFunctionPlanFor(siblingChild.expression, siblingB.binding));
		expectThrows("foreign-root-identities",
			() -> siblingRegistry.sealNestedFunction(siblingA.expression, siblingA.externalLocals, siblingA.binding.bodyRevision, siblingA.plan,
				siblingIdentities));
		final refreshedSiblingIdentities = LexicalLocalIdentityPlan.build(siblingRoot.functionId, siblingOwnerBody);
		siblingRegistry.registerRootIdentityPlan(siblingRoot, refreshedSiblingIdentities);
		siblingRegistry.sealNestedFunction(siblingA.expression, siblingA.externalLocals, siblingA.binding.bodyRevision, siblingA.plan,
			refreshedSiblingIdentities);
		siblingRegistry.sealNestedFunction(siblingB.expression, siblingB.externalLocals, siblingB.binding.bodyRevision, siblingB.plan,
			refreshedSiblingIdentities);
		siblingRegistry.sealNestedFunction(siblingChild.expression, siblingChild.externalLocals, siblingChild.binding.bodyRevision, siblingChild.plan,
			refreshedSiblingIdentities);
		if (siblingRegistry.nestedFunctionPlanFor(siblingChild.expression, siblingB.binding) == null)
			throw "The same-program reset did not rebuild the exact nested-parent plan";

		final childExpression = Context.typeExpr(macro function(value:Int):Int return value);
		final childExternalLocals = nestedExternalLocals(childExpression);
		nestedRegistry.deferNestedFunction(childExpression, admittedBinding, childExternalLocals, nestedBodyRevision(childExpression, childExternalLocals),
			"fixture proves an admitted nested parent can own a deeper literal");
		if (nestedRegistry.nestedFunctionPlanFor(childExpression, admittedBinding) != null)
			throw "A deliberately deferred child of an admitted nested function unexpectedly returned a plan";

		expectThrows("duplicate-occurrence",
			() -> nestedRegistry.sealNestedFunction(admittedExpression, admittedExternalLocals, admittedBinding.bodyRevision, admittedPlan,
				admittedIdentities));

		final mismatchedExpression = Context.typeExpr(macro function(value:Int):Int {
			if (value > 0)
				return 7;
			return 0;
		});
		final mismatchedFunction = switch (mismatchedExpression.expr) {
			case TFunction(tfunc): tfunc;
			case _: throw "The nested result-mismatch fixture did not type as a function literal";
		};
		final mismatchedExternalLocals = nestedExternalLocals(mismatchedExpression);
		final mismatchedIdentities = LexicalLocalIdentityPlan.build(otherParent.functionId, mismatchedExpression);
		nestedRegistry.registerRootIdentityPlan(otherParent, mismatchedIdentities);
		final mismatchedBinding = nestedFunctionBinding(otherParent, mismatchedExpression, mismatchedExternalLocals, mismatchedIdentities);
		final mismatchedReturn = firstReturn(mismatchedFunction.expr);
		final mismatchedReturnSource = OcamlLoweredOrigin.sourceSpan(mismatchedReturn.pos);
		final mismatchedDecision = returnDecision("control:return:nested-result-mismatch", mismatchedReturnSource.min, mismatchedBinding.functionId, null,
			null, "Int", null, null, mismatchedBinding, mismatchedReturnSource);
		final mismatchedControls = new OcamlControlPlan(true, true, true, mismatchedBinding, [], [mismatchedDecision], [],
			[{expression: mismatchedReturn, decisionId: mismatchedDecision.id}], [], []);
		final mismatchedPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: mismatchedIdentities.requireFunctionOccurrence(mismatchedExpression).id,
			parentBinding: otherParent,
			binding: mismatchedBinding,
			callableBoundary: nestedBoundary(mismatchedBinding, "Bool"),
			controls: mismatchedControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("return-boundary-mismatch",
			() -> nestedRegistry.sealNestedFunction(mismatchedExpression, mismatchedExternalLocals, mismatchedBinding.bodyRevision, mismatchedPlan,
				mismatchedIdentities));

		// An unsupported throw is removed from the planner's decision list. This
		// deliberately corrupt plan proves the catalog checks the family flag and
		// cannot mistake the surviving return for a return-only closure.
		final unadmittedThrowControls = new OcamlControlPlan(true, true, false, mismatchedBinding, [], [mismatchedDecision], [],
			[{expression: mismatchedReturn, decisionId: mismatchedDecision.id}], [], []);
		final unadmittedThrowPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: mismatchedPlan.occurrenceId,
			parentBinding: otherParent,
			binding: mismatchedBinding,
			callableBoundary: nestedBoundary(mismatchedBinding),
			controls: unadmittedThrowControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("unsupported-control",
			() -> nestedRegistry.sealNestedFunction(mismatchedExpression, mismatchedExternalLocals, mismatchedBinding.bodyRevision, unadmittedThrowPlan,
				mismatchedIdentities));

		final unadmittedLoopControls = new OcamlControlPlan(true, false, true, mismatchedBinding, [], [mismatchedDecision], [],
			[{expression: mismatchedReturn, decisionId: mismatchedDecision.id}], [], []);
		final unadmittedLoopPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: mismatchedPlan.occurrenceId,
			parentBinding: otherParent,
			binding: mismatchedBinding,
			callableBoundary: nestedBoundary(mismatchedBinding),
			controls: unadmittedLoopControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("unsupported-control",
			() -> nestedRegistry.sealNestedFunction(mismatchedExpression, mismatchedExternalLocals, mismatchedBinding.bodyRevision, unadmittedLoopPlan,
				mismatchedIdentities));

		// A loop target or transfer sealed for an ordinary function must not become
		// valid merely because a nested plan has the same control kind. These records
		// deliberately retain the fixture's ordinary binding and must fail before the
		// nested catalog or OCaml syntax can observe them.
		final foreignNestedLoopTarget = loopTarget("control-target:loop:nested-foreign", 520);
		expectThrows("stale-target", () -> new OcamlControlPlan(true, true, true, mismatchedBinding, [foreignNestedLoopTarget], [mismatchedDecision]));
		final foreignNestedBreak = loopDecision("control:break:nested-foreign", 530, foreignNestedLoopTarget.id, OcamlControlTransferKind.Break);
		expectThrows("stale-binding", () -> new OcamlControlPlan(true, true, true, mismatchedBinding, [], [foreignNestedBreak]));

		final caughtExpression = Context.typeExpr(macro function(value:Int):Int {
			try {
				if (value > 0)
					return 6;
			} catch (_:Dynamic) {}
			return 0;
		});
		final caughtFunction = switch (caughtExpression.expr) {
			case TFunction(tfunc): tfunc;
			case _: throw "The nested catch-completeness fixture did not type as a function literal";
		};
		final caughtExternalLocals = nestedExternalLocals(caughtExpression);
		final caughtParent:OcamlFunctionPlanBinding = {
			functionId: "Main|Main|static|function|caughtOwner|generics:0|->Int",
			programRevision: nestedParent.programRevision,
			bodyRevision: nestedParent.bodyRevision,
			pipelineRevision: nestedParent.pipelineRevision
		};
		final caughtIdentities = LexicalLocalIdentityPlan.build(caughtParent.functionId, caughtExpression);
		nestedRegistry.registerRootIdentityPlan(caughtParent, caughtIdentities);
		final caughtBinding = nestedFunctionBinding(caughtParent, caughtExpression, caughtExternalLocals, caughtIdentities);
		final caughtReturn = firstReturn(caughtFunction.expr);
		final caughtReturnSource = OcamlLoweredOrigin.sourceSpan(caughtReturn.pos);
		final caughtDecision = returnDecision("control:return:nested-caught", caughtReturnSource.min, caughtBinding.functionId, null, null, "Int", null, null,
			caughtBinding, caughtReturnSource);
		final caughtTry = firstTry(caughtFunction.expr);
		// A catch chain from an ordinary function cannot be attached to a nested
		// function merely because its source shape looks compatible. Construction
		// must reject the foreign function and revision before the catalog or target
		// syntax can observe it.
		final foreignCaughtChain = catchChain("control-catch-chain:nested-foreign", [
			catchClause("control-catch-clause:nested-foreign", caughtReturnSource.min, 0, "_", "Dynamic")
		]);
		expectThrows("stale-catch-chain",
			() -> new OcamlControlPlan(true, true, true, caughtBinding, [], [caughtDecision], [], [{expression: caughtReturn, decisionId: caughtDecision.id}],
				[foreignCaughtChain], [
				{
					expression: caughtTry,
					occurrenceId: "catch-occurrence:nested-foreign",
					source: OcamlLoweredOrigin.sourceSpan(caughtTry.pos),
					chainId: foreignCaughtChain.id
				}
			]));
		// An observed nested try with no admitted chain is a deliberate legacy
		// disposition. The registry must reject it now that nested catches are
		// allowed, rather than confusing "observed" with "fully represented".
		final caughtControls = new OcamlControlPlan(true, true, true, caughtBinding, [], [caughtDecision], [],
			[{expression: caughtReturn, decisionId: caughtDecision.id}], [], [
			{
				expression: caughtTry,
				occurrenceId: "catch-occurrence:nested-caught",
				source: OcamlLoweredOrigin.sourceSpan(caughtTry.pos),
				chainId: null
			}
		]);
		final caughtPlan:OcamlSealedNestedFunctionPlan = {
			occurrenceId: caughtIdentities.requireFunctionOccurrence(caughtExpression).id,
			parentBinding: caughtParent,
			binding: caughtBinding,
			callableBoundary: nestedBoundary(caughtBinding),
			controls: caughtControls,
			arrayLiteralProducers: noArrayLiteralProducers
		};
		expectThrows("unsupported-control",
			() -> nestedRegistry.sealNestedFunction(caughtExpression, caughtExternalLocals, caughtBinding.bodyRevision, caughtPlan, caughtIdentities));

		Reflect.setField(admittedFunction, "expr", Context.typeExpr(macro 99));
		expectThrows("stale-body", () -> nestedRegistry.nestedFunctionPlanFor(admittedExpression, nestedParent));

		Sys.println("REFLAXE_OCAML_CONTROL_PLAN_FIXTURE:PASS");
		return macro null;
	}
}
