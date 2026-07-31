package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlEnumDynamicCarrier;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementDecision;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementRole;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Explains why one sealed enum operation needs the generated `HxEnum` helper.

	The generated-module scan can confirm that emitted OCaml mentions `HxEnum`,
	but it cannot explain which Haxe expression required that module. This
	recorder maps an already checked enum-to-`Dynamic` conversion or direct enum
	throw to one source-owned runtime reason. It does not inspect generated text
	or infer a new enum decision, so packaging can trace the helper back to the
	exact Haxe expression that required it.
**/
class OcamlEnumRuntimeRequirementRecorder {
	/** Builds the one runtime requirement owned by an admitted conversion. */
	public static function requirement(conversion:OcamlLocalConversionDecision):OcamlRuntimeRequirement {
		if (conversion.conversion != OcamlLocalCarrierConversion.BoxExactEnumToDynamic
			|| conversion.role != OcamlLocalConversionRole.Initializer
			|| conversion.outputSemanticTypeId != "Dynamic"
			|| conversion.outputCarrierTypeId != OcamlEnumDynamicCarrier.DYNAMIC_CARRIER) {
			throw 'reflaxe.ocaml [ocaml-enum:wrong-runtime-conversion]: local conversion "${conversion.id}" is not an exact enum-to-Dynamic initializer';
		}
		OcamlEnumDynamicCarrier.requireIdentity(conversion.inputSemanticTypeId, conversion.inputCarrierTypeId);
		final unsafe = conversion.unsafeOperation;
		if (unsafe == null
			|| unsafe.conversionId != conversion.id
			|| unsafe.operation != OcamlUnsafeOperationKind.BoxExactEnumToDynamic
			|| unsafe.inputSemanticTypeId != conversion.inputSemanticTypeId
			|| unsafe.inputCarrierTypeId != conversion.inputCarrierTypeId
			|| unsafe.outputSemanticTypeId != conversion.outputSemanticTypeId
			|| unsafe.outputCarrierTypeId != conversion.outputCarrierTypeId) {
			throw 'reflaxe.ocaml [ocaml-enum:wrong-runtime-proof]: local conversion "${conversion.id}" does not own the exact enum boxing proof';
		}
		return {
			id: OcamlEnumDynamicCarrier.runtimeRequirementId(conversion.id),
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: conversion.id,
			source: conversion.source,
			semanticCapability: OcamlEnumDynamicCarrier.RUNTIME_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: conversion.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: conversion.inputSemanticTypeId
			},
			implementationFeature: OcamlEnumDynamicCarrier.RUNTIME_FEATURE,
			rootModules: [OcamlEnumDynamicCarrier.RUNTIME_MODULE],
			profileEligibility: conversion.profileEligibility,
			explanation: 'The sealed initializer converts ${conversion.inputSemanticTypeId} from its native OCaml variant into Dynamic by calling ${OcamlEnumDynamicCarrier.RUNTIME_MODULE}.${OcamlEnumDynamicCarrier.RUNTIME_OPERATION}; this preserves constant-constructor identity and payload values.'
		};
	}

	/** Adds the admitted enum conversion to the request-owned runtime ledger. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, conversion:OcamlLocalConversionDecision):Void {
		ledger.record(requirement(conversion));
	}

	/** Builds the runtime reason owned by one `Array<Dynamic>` element conversion. */
	public static function containerElementRequirement(decision:OcamlContainerElementDecision):OcamlRuntimeRequirement {
		// Reconstructing a one-entry plan reuses the same fail-closed contract as
		// function sealing and catches a forged report or request handoff.
		new OcamlContainerElementPlan([decision]);
		if (decision.role != OcamlContainerElementRole.ArrayLiteralDynamicElement
			|| decision.conversion != OcamlLocalCarrierConversion.BoxExactEnumToDynamic
			|| decision.outputSemanticTypeId != "Dynamic"
			|| decision.outputCarrierTypeId != OcamlEnumDynamicCarrier.DYNAMIC_CARRIER) {
			throw 'reflaxe.ocaml [ocaml-enum:wrong-runtime-container-element]: conversion "${decision.id}" is not an exact enum-to-Dynamic array element';
		}
		return {
			id: OcamlEnumDynamicCarrier.runtimeRequirementId(decision.id),
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: OcamlEnumDynamicCarrier.RUNTIME_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: decision.inputSemanticTypeId
			},
			implementationFeature: OcamlEnumDynamicCarrier.RUNTIME_FEATURE,
			rootModules: [OcamlEnumDynamicCarrier.RUNTIME_MODULE],
			profileEligibility: decision.profileEligibility,
			explanation: 'The sealed Array<Dynamic> element converts ${decision.inputSemanticTypeId} from its native OCaml variant into Dynamic by calling ${OcamlEnumDynamicCarrier.RUNTIME_MODULE}.${OcamlEnumDynamicCarrier.RUNTIME_OPERATION}; this preserves its enum identity and payload after array storage.'
		};
	}

	/** Adds one admitted enum array element to the request-owned runtime ledger. */
	public static function recordContainerElement(ledger:OcamlRuntimeRequirementLedger, decision:OcamlContainerElementDecision):Void {
		ledger.record(containerElementRequirement(decision));
	}

	/**
		Builds the runtime reason for one directly thrown enum constructor.

		The control decision already owns the enum identity, source occurrence,
		private exception carrier, and exact tags. This method only maps that
		sealed behavior to the checked `HxEnum` source module.
	**/
	public static function throwRequirement(decision:OcamlControlDecision):OcamlRuntimeRequirement {
		final payload = decision.payload;
		if (payload == null || !OcamlControlPlan.isAdmittedEnumThrowPayload(payload)) {
			throw 'reflaxe.ocaml [ocaml-enum:wrong-runtime-throw]: control decision "${decision.id}" is not a sealed direct enum-constructor throw';
		}
		return {
			id: OcamlEnumDynamicCarrier.runtimeRequirementId(decision.id),
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: OcamlEnumDynamicCarrier.RUNTIME_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: payload.inputSemanticTypeId
			},
			implementationFeature: OcamlEnumDynamicCarrier.RUNTIME_FEATURE,
			rootModules: [OcamlEnumDynamicCarrier.RUNTIME_MODULE],
			profileEligibility: decision.profileEligibility,
			explanation: 'The sealed throw evaluates one direct ${payload.inputSemanticTypeId} constructor and calls ${OcamlEnumDynamicCarrier.RUNTIME_MODULE}.${OcamlEnumDynamicCarrier.RUNTIME_OPERATION} with that enum name before the value enters the private exception carrier.'
		};
	}

	/** Adds one direct enum-constructor throw to the request-owned runtime ledger. */
	public static function recordThrow(ledger:OcamlRuntimeRequirementLedger, decision:OcamlControlDecision):Void {
		ledger.record(throwRequirement(decision));
	}
}
#end
