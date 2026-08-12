package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadContract;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadDecision;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorContract;
import reflaxe.ocaml.lowered.OcamlArrayIteratorPlan.OcamlArrayIteratorDecision;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan;
import reflaxe.ocaml.lowered.OcamlClassIdentityMarkerPlan.OcamlClassIdentityMarkerDecision;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityDecision;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringDecision;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlReflectRuntimeUsePlan.OcamlReflectRuntimeUseDecision;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan.OcamlStdIsOfTypeDecision;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryDecision;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodeDecision;
import reflaxe.ocaml.lowered.OcamlStringFromCharCodePlan.OcamlStringFromCharCodeForm;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan.OcamlStringEqualityDecision;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan;
import reflaxe.ocaml.lowered.OcamlStringMethodPlan.OcamlStringMethodDecision;
import reflaxe.ocaml.lowered.OcamlStringFieldPlan;
import reflaxe.ocaml.lowered.OcamlStringFieldPlan.OcamlStringFieldDecision;
import reflaxe.ocaml.lowered.OcamlDynamicBracketReadModel.OcamlDynamicBracketReadContract;
import reflaxe.ocaml.lowered.OcamlDynamicBracketReadModel.OcamlDynamicBracketReadDecision;
#if macro
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel.OcamlCatchRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlLoopRuntimeUseModel.OcamlLoopRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlReturnRuntimeUseModel.OcamlReturnRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlThrowRuntimeUseModel.OcamlThrowRuntimeUseContract;
#end
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceContract;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallTarget;
import reflaxe.ocaml.lowered.OcamlStandardContainerCarrierModel.OcamlStandardContainerCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardContainerCarrierModel.OcamlStandardContainerCarrierDecision;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierDecision;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallTarget;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

using StringTools;

/**
	Collects immutable explanations for compatibility-runtime use in one compile.

	Entries are recorded where a target decision is made. Later packaging may read
	the sorted records, but it must not invent or reinterpret why the support is
	needed.
**/
class OcamlRuntimeRequirementLedger {
	public static inline final INT32_ADD = "haxe-int32-add";
	public static inline final ARRAY_ELEMENT_GET = "haxe-array-element-get";
	public static inline final ARRAY_ELEMENT_SET = "haxe-array-element-set";
	public static inline final ARRAY_LITERAL_CONSTRUCTION = "haxe-array-literal-construction";
	public static inline final STRING_NULL_SENTINEL = "haxe-string-null-sentinel";
	public static inline final STRING_FROM_CHAR_CODE = "haxe-string-from-char-code";
	public static inline final STRING_EQUALITY = "haxe-string-equality";
	public static inline final STRING_METHOD = "haxe-string-method";
	public static inline final STRING_FIELD = "haxe-string-field-read";
	public static inline final NULLABLE_PRIMITIVE_FIELD_DEFAULT = "haxe-nullable-primitive-field-default";
	public static inline final CORE_RUNTIME = "compiler-core-runtime";
	public static inline final TYPE_REGISTRY = "compiler-type-registry";
	public static inline final TYPE_REGISTRY_DYNAMIC_ARGS = "compiler-type-registry-dynamic-args";
	public static inline final TYPE_REGISTRY_OPTIONAL_NULL = "compiler-type-registry-optional-null";
	public static inline final TYPE_REGISTRY_OPTIONAL_STRING_NULL = "compiler-type-registry-optional-string-null";
	public static inline final TYPE_REGISTRY_RUNTIME_UNBOX = "compiler-type-registry-runtime-unbox";
	public static inline final TYPE_REGISTRY_DYNAMIC_STRING = "compiler-type-registry-dynamic-string";
	public static inline final HXHX_BACKEND_PLUGIN_HOST = "hxhx-backend-plugin-host";
	public static inline final HAXE_STANDARD_IO = "haxe-standard-io";
	public static inline final HAXE_STACK_TRACES = "haxe-stack-traces";
	public static inline final HAXE_FLOAT_BIT_CONVERSIONS = "haxe-float-bit-conversions";
	public static inline final HAXE_PROCESS = "haxe-process";
	public static inline final HAXE_FILE = "haxe-file";
	public static inline final HAXE_FILE_STREAM = "haxe-file-stream";
	public static inline final HAXE_THREAD = "haxe-thread";
	public static inline final HAXE_FILE_SYSTEM = "haxe-file-system";
	public static inline final HAXE_SYSTEM = "haxe-system";
	public static inline final HAXE_MAP = "haxe-map";
	public static inline final HAXE_ITERATOR = "haxe-iterator";
	public static inline final HAXE_DYNAMIC_EQUALITY = "haxe-dynamic-equality";
	public static inline final HAXE_DYNAMIC_STRING = "haxe-dynamic-string";
	public static inline final HAXE_ARRAY = "haxe-array";
	public static inline final HAXE_STRING_TEXT = "haxe-string-text";
	public static inline final HAXE_DYNAMIC_TEXT = "haxe-dynamic-text";
	public static inline final HAXE_REFLECT_COMPARE_FAILURE = "haxe-reflect-compare-failure";
	public static inline final HAXE_REFLECT_RUNTIME_CALL = "haxe-reflect-runtime-call";
	public static inline final HAXE_STD_IS_OF_TYPE = "haxe-std-is-of-type";
	public static inline final HAXE_INT32_UNARY = "haxe-int32-unary";

	var currentProgramRevision:Null<String> = null;
	final byId:Map<String, OcamlRuntimeRequirement> = [];

	public function new() {}

	/** Starts one compile and discards every requirement from the prior program. **/
	public function beginProgram(programRevision:String):Void {
		final revision = required(programRevision, "program revision");
		currentProgramRevision = revision;
		byId.clear();
	}

	/** Records one requirement and rejects reused identities with different facts. **/
	public function record(requirement:OcamlRuntimeRequirement):Void {
		if (currentProgramRevision == null)
			throw "OCaml runtime requirements cannot be recorded before the program revision begins.";
		final normalized = normalize(requirement);
		final existing = byId.get(normalized.id);
		if (existing != null) {
			if (Json.stringify(existing) != Json.stringify(normalized))
				throw 'OCaml runtime requirement identity "${normalized.id}" was reused with different facts.';
			return;
		}
		byId.set(normalized.id, normalized);
	}

	/**
		Expands the closed capability IDs on one sealed place plan into complete
		Haxe-expression runtime requirements.
	**/
	public function recordPlacePlan(decisionId:String, originId:String, source:OcamlLoweredSourceSpan, semanticTypeId:String,
			requirementIds:Array<String>):Void {
		for (requirementId in requirementIds)
			record(requirementForPlaceCapability(decisionId, originId, originId, source, semanticTypeId, requirementId));
	}

	/** Returns the direct HxMap dependency selected by one standard Map carrier. */
	public static function requirementsForStandardMapCarrier(decision:OcamlStandardMapCarrierDecision):Array<OcamlRuntimeRequirement> {
		OcamlStandardMapCarrierContract.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
				sourceId: decision.sourceDeclarationId,
				source: decision.source,
				semanticCapability: HAXE_MAP,
				cause: OcamlRuntimeRequirementCause.RepresentationDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: 'Map<${decision.keySemanticTypeId}, ${decision.valueSemanticTypeId}>'
				},
				implementationFeature: "haxe-map-v1",
				rootModules: ["HxMap"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed standard Haxe Map type uses the selected HxMap carrier to preserve string, integer, or object-identity key behavior."
			})
		];
	}

	/** Records the direct HxMap dependency selected by one standard Map carrier. */
	public function recordStandardMapCarrier(decision:OcamlStandardMapCarrierDecision):Void {
		for (requirement in requirementsForStandardMapCarrier(decision))
			record(requirement);
	}

	/** Returns the direct runtime dependency for one standard Array or Bytes type. */
	public static function requirementsForStandardContainerCarrier(decision:OcamlStandardContainerCarrierDecision):Array<OcamlRuntimeRequirement> {
		OcamlStandardContainerCarrierContract.requireDecision(decision);
		final runtimeModule = OcamlStandardContainerCarrierContract.runtimeModuleForKind(decision.kind);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
				sourceId: decision.sourceDeclarationId,
				source: decision.source,
				semanticCapability: OcamlStandardContainerCarrierContract.runtimeCapabilityForKind(decision.kind),
				cause: OcamlRuntimeRequirementCause.RepresentationDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.semanticTypeId
				},
				implementationFeature: OcamlStandardContainerCarrierContract.implementationFeatureForKind(decision.kind),
				rootModules: [runtimeModule],
				profileEligibility: decision.profileEligibility,
				explanation: 'The sealed standard Haxe ${decision.sourceDeclarationId} type uses $runtimeModule as its concrete mutable OCaml carrier.'
			})
		];
	}

	/** Records the direct runtime dependency selected by one Array or Bytes type. */
	public function recordStandardContainerCarrier(decision:OcamlStandardContainerCarrierDecision):Void {
		for (requirement in requirementsForStandardContainerCarrier(decision))
			record(requirement);
	}

	/** Returns the direct HxType dependency for one generated class record. */
	public static function requirementsForClassIdentityMarker(decision:OcamlClassIdentityMarkerDecision):Array<OcamlRuntimeRequirement> {
		OcamlClassIdentityMarkerPlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
				sourceId: decision.sourceDeclarationId,
				source: decision.source,
				semanticCapability: OcamlClassIdentityMarkerPlan.RUNTIME_CAPABILITY,
				cause: OcamlRuntimeRequirementCause.RepresentationDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.sourceDeclarationId
				},
				implementationFeature: OcamlClassIdentityMarkerPlan.IMPLEMENTATION_FEATURE,
				rootModules: ["HxType"],
				profileEligibility: decision.profileEligibility,
				explanation: 'The generated ${decision.emissionRole} for ${decision.sourceDeclarationId} stores the exact Haxe runtime class marker used by Type.getClass.'
			})
		];
	}

	/** Records the direct HxType dependency for one generated class record. */
	public function recordClassIdentityMarker(decision:OcamlClassIdentityMarkerDecision):Void {
		for (requirement in requirementsForClassIdentityMarker(decision))
			record(requirement);
	}

	/**
		Builds one checked runtime reason for field, array, or similar place work.

		`originId` scopes the requirement identity to the sealed lowering
		decision. `sourceId` names the Haxe occurrence shown to a report reader.
		Keeping both explicit lets another sealed model reuse Haxe Int32
		arithmetic without copying the module-selection policy.
	**/
	public static function requirementForPlaceCapability(decisionId:String, originId:String, sourceId:String, source:OcamlLoweredSourceSpan,
			semanticTypeId:String, requirementId:String):OcamlRuntimeRequirement {
		final expectedPrefix = originId + ":runtime:";
		if (!requirementId.startsWith(expectedPrefix))
			throw 'Place runtime requirement "$requirementId" is not scoped to origin "$originId".';
		final capability = requirementId.substr(expectedPrefix.length);
		final implementation = placeImplementation(capability);
		return normalize({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: sourceId,
			source: source,
			semanticCapability: capability,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decisionId,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: semanticTypeId
			},
			implementationFeature: implementation.feature,
			rootModules: [implementation.module],
			profileEligibility: ["metal", "portable"],
			explanation: implementation.explanation
		});
	}

	/**
		Returns the complete runtime explanations selected by one standard `IMap`
		call before OCaml syntax.
	**/
	public static function requirementsForStandardIMapCall(callId:String, source:OcamlLoweredSourceSpan, profileEligibility:Array<String>,
			target:OcamlStandardIMapCallTarget):Array<OcamlRuntimeRequirement> {
		OcamlStandardIMapCallContract.require(target);
		final stableCallId = required(callId, "standard IMap call identity");
		if (source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'Standard IMap call "$stableCallId" has an invalid source occurrence.';
		if (profileEligibility.length != 2 || profileEligibility[0] != "metal" || profileEligibility[1] != "portable")
			throw 'Standard IMap call "$stableCallId" has an unsupported profile inventory.';
		final requirementIds = OcamlStandardIMapCallContract.runtimeRequirementIds(stableCallId, target);
		final out:Array<OcamlRuntimeRequirement> = [];
		for (index in 0...target.runtimeCapabilities.length) {
			final capability = target.runtimeCapabilities[index];
			final implementation = standardIMapImplementation(capability);
			out.push(normalize({
				id: requirementIds[index],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: stableCallId,
				source: source,
				semanticCapability: capability,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: stableCallId,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: target.receiverSemanticTypeId
				},
				implementationFeature: implementation.feature,
				rootModules: [implementation.module],
				profileEligibility: profileEligibility,
				explanation: implementation.explanation
			}));
		}
		return out;
	}

	/** Records every runtime dependency selected by one sealed standard `IMap` call. **/
	public function recordStandardIMapCall(callId:String, source:OcamlLoweredSourceSpan, profileEligibility:Array<String>,
			target:OcamlStandardIMapCallTarget):Void {
		for (requirement in requirementsForStandardIMapCall(callId, source, profileEligibility, target))
			record(requirement);
	}

	/** Returns runtime explanations selected by one complete standard-Map interface adapter. */
	public static function requirementsForIMapInterfaceConversion(decision:OcamlIMapInterfaceConversionDecision):Array<OcamlRuntimeRequirement> {
		OcamlIMapInterfaceContract.requireConversion(decision);
		final requirementIds = OcamlIMapInterfaceContract.runtimeRequirementIds(decision);
		final out:Array<OcamlRuntimeRequirement> = [];
		for (index in 0...decision.runtimeCapabilities.length) {
			final capability = decision.runtimeCapabilities[index];
			final implementation = standardIMapImplementation(capability);
			out.push(normalize({
				id: requirementIds[index],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: capability,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.targetSemanticTypeId
				},
				implementationFeature: implementation.feature,
				rootModules: [implementation.module],
				profileEligibility: ["metal", "portable"],
				explanation: "The sealed concrete-to-IMap adapter exposes the IMap methods retained for this program. " + implementation.explanation
			}));
		}
		return out;
	}

	/** Records the runtime dependencies owned by one concrete-to-interface conversion. */
	public function recordIMapInterfaceConversion(decision:OcamlIMapInterfaceConversionDecision):Void {
		for (requirement in requirementsForIMapInterfaceConversion(decision))
			record(requirement);
	}

	/** Returns the runtime reason owned by one nullable standard-Map storage alias. */
	public static function requirementsForIMapStorageAlias(decision:OcamlIMapStorageAliasDecision):Array<OcamlRuntimeRequirement> {
		OcamlIMapInterfaceContract.requireStorageAlias(decision);
		if (decision.runtimeRequirementIds.length == 0)
			return [];
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: OcamlStandardIMapCallContract.CORE_RUNTIME_CAPABILITY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.sourceSemanticTypeId
				},
				implementationFeature: "haxe-runtime-core-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: "The sealed nullable standard-Map storage alias uses HxRuntime to test its erased source carrier and raise catchable Haxe Null Access before recovering the exact non-null Map carrier."
			})
		];
	}

	/** Records the runtime dependency selected by one nullable storage alias. */
	public function recordIMapStorageAlias(decision:OcamlIMapStorageAliasDecision):Void {
		for (requirement in requirementsForIMapStorageAlias(decision))
			record(requirement);
	}

	/**
		Returns the runtime reason owned by one direct structural Iterator call.

		This record connects a particular Haxe `hasNext()` or `next()` occurrence
		to `HxIterator`. Packaging can therefore include the module because a
		sealed compiler decision requested it, rather than merely because generated
		text happened to mention the module name.
	**/
	public static function requirementsForStructuralIteratorCall(callId:String, source:OcamlLoweredSourceSpan, profileEligibility:Array<String>,
			target:OcamlStructuralIteratorCallTarget):Array<OcamlRuntimeRequirement> {
		OcamlStructuralIteratorCallContract.require(target);
		final stableCallId = required(callId, "structural Iterator call identity");
		if (source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'Structural Iterator call "$stableCallId" has an invalid source occurrence.';
		if (profileEligibility.length != 2 || profileEligibility[0] != "metal" || profileEligibility[1] != "portable")
			throw 'Structural Iterator call "$stableCallId" has an unsupported profile inventory.';
		return [
			normalize({
				id: OcamlStructuralIteratorCallContract.runtimeRequirementIds(stableCallId, target)[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: stableCallId,
				source: source,
				semanticCapability: HAXE_ITERATOR,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: stableCallId,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: target.receiverSemanticTypeId
				},
				implementationFeature: "haxe-iterator-v1",
				rootModules: [target.runtimeModule],
				profileEligibility: profileEligibility,
				explanation: "The sealed direct structural Iterator call uses HxIterator to invoke the selected hasNext or next operation after evaluating the receiver exactly once."
			})
		];
	}

	/** Records the runtime dependency selected by one direct structural Iterator call. */
	public function recordStructuralIteratorCall(callId:String, source:OcamlLoweredSourceSpan, profileEligibility:Array<String>,
			target:OcamlStructuralIteratorCallTarget):Void {
		for (requirement in requirementsForStructuralIteratorCall(callId, source, profileEligibility, target))
			record(requirement);
	}

	/** Returns a runtime reason only when this Array iterator decision uses `HxIterator`. */
	public static function requirementsForArrayIterator(decision:OcamlArrayIteratorDecision):Array<OcamlRuntimeRequirement> {
		OcamlArrayIteratorContract.requireDecision(decision);
		if (decision.runtimeRequirementIds.length == 0)
			return [];
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_ITERATOR,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.resultSemanticTypeId
				},
				implementationFeature: "haxe-iterator-v1",
				rootModules: ["HxIterator"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed occurrence uses HxIterator only for an exact Array-to-Iterable adapter or a structural Iterator carrier. Direct and stored Array.iterator calls return the standard generated ArrayIterator class instead."
			})
		];
	}

	/** Records the runtime dependency selected by one Array iterator reference. */
	public function recordArrayIterator(decision:OcamlArrayIteratorDecision):Void {
		for (requirement in requirementsForArrayIterator(decision))
			record(requirement);
	}

	/** Returns the exact HxRuntime reason for one sealed Dynamic equality call. */
	public static function requirementsForDynamicEquality(decision:OcamlDynamicEqualityDecision):Array<OcamlRuntimeRequirement> {
		OcamlDynamicEqualityPlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_DYNAMIC_EQUALITY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.leftSemanticTypeId + " == " + decision.rightSemanticTypeId
				},
				implementationFeature: "haxe-dynamic-equality-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: decision.profileEligibility,
				explanation: "The final typed equality or switch case uses the Dynamic value representation. This checked HxRuntime.dynamic_equals call preserves Haxe rules for numbers, Booleans, enums, strings, null values, and object identity."
			})
		];
	}

	/** Records the runtime dependency selected by one Dynamic equality decision. */
	public function recordDynamicEquality(decision:OcamlDynamicEqualityDecision):Void {
		for (requirement in requirementsForDynamicEquality(decision))
			record(requirement);
	}

	/** Returns the exact HxDynamic reason for one sealed standard string conversion. */
	public static function requirementsForDynamicString(decision:OcamlDynamicStringDecision):Array<OcamlRuntimeRequirement> {
		OcamlDynamicStringPlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_DYNAMIC_STRING,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.semanticTypeId
				},
				implementationFeature: "haxe-dynamic-string-v1",
				rootModules: ["HxDynamic"],
				profileEligibility: decision.profileEligibility,
				explanation: "The final typed expression needs Haxe standard string behavior and has no selected static conversion. The checked HxDynamic.toStdString call preserves null, primitive, registered class, enum, and fallback object formatting."
			})
		];
	}

	/** Records the runtime dependency selected by one Dynamic string decision. */
	public function recordDynamicString(decision:OcamlDynamicStringDecision):Void {
		for (requirement in requirementsForDynamicString(decision))
			record(requirement);
	}

	/** Returns the exact HxReflect reason for one sealed standard Reflect call. */
	public static function requirementsForReflectRuntimeUse(decision:OcamlReflectRuntimeUseDecision):Array<OcamlRuntimeRequirement> {
		OcamlReflectRuntimeUsePlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_REFLECT_RUNTIME_CALL,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Reflect."
					+ decision.sourceMethod
					+ ":"
					+ decision.argumentSemanticTypeIds.join(",")
					+ "->"
					+ decision.resultSemanticTypeId},
				implementationFeature: "haxe-direct-reflect-call-v1",
				rootModules: ["HxReflect"],
				profileEligibility: decision.profileEligibility,
				explanation: "The resolved standard Reflect call selected one private HxReflect operation. The compiler records this one generated identifier before it writes OCaml, so another HxReflect use cannot borrow the same permission."
			})
		];
	}

	/** Records the runtime dependency selected by one direct standard Reflect call. */
	public function recordReflectRuntimeUse(decision:OcamlReflectRuntimeUseDecision):Void {
		for (requirement in requirementsForReflectRuntimeUse(decision))
			record(requirement);
	}

	/** Returns the exact runtime roots selected by one sealed `Std.isOfType()` call. */
	public static function requirementsForStdIsOfType(decision:OcamlStdIsOfTypeDecision):Array<OcamlRuntimeRequirement> {
		OcamlStdIsOfTypePlan.requireDecision(decision);
		if (decision.runtimeRequirementIds.length == 0)
			return [];
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_STD_IS_OF_TYPE,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.valueSemanticTypeId + " is " + decision.requestedTypeSemanticId
				},
				implementationFeature: "haxe-std-is-of-type-v1",
				rootModules: OcamlStdIsOfTypePlan.rootModules(decision),
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed standard Haxe type check selected one dynamic primitive check or the general runtime type test. Its private helper names are fixed before target syntax."
			})
		];
	}

	/** Records the private helpers selected by one sealed `Std.isOfType()` call. */
	public function recordStdIsOfType(decision:OcamlStdIsOfTypeDecision):Void {
		for (requirement in requirementsForStdIsOfType(decision))
			record(requirement);
	}

	/** Returns the exact runtime roots selected by one integer unary expression. */
	public static function requirementsForIntUnary(decision:OcamlIntUnaryDecision):Array<OcamlRuntimeRequirement> {
		OcamlIntUnaryPlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_INT32_UNARY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.operandSemanticTypeId + " -> " + decision.resultSemanticTypeId
				},
				implementationFeature: "haxe-int32-unary-v1",
				rootModules: OcamlIntUnaryPlan.rootModules(decision),
				profileEligibility: decision.profileEligibility,
				explanation: "The final typed integer unary expression selected its Int32 operation and nullable conversion before target syntax. The listed private helper names are the complete allowed sequence for this source occurrence."
			})
		];
	}

	/** Records the private helpers selected by one integer unary expression. */
	public function recordIntUnary(decision:OcamlIntUnaryDecision):Void {
		for (requirement in requirementsForIntUnary(decision))
			record(requirement);
	}

	/** Returns the runtime roots selected by one `String.fromCharCode` expression. */
	public static function requirementsForStringFromCharCode(decision:OcamlStringFromCharCodeDecision):Array<OcamlRuntimeRequirement> {
		OcamlStringFromCharCodePlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: STRING_FROM_CHAR_CODE,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.form == OcamlStringFromCharCodeForm.DirectCall ? '${decision.argumentSemanticTypeId} -> String' : "String.fromCharCode function value"
				},
				implementationFeature: "haxe-string-from-char-code-v1",
				rootModules: OcamlStringFromCharCodePlan.rootModules(decision),
				profileEligibility: decision.profileEligibility,
				explanation: "The final typed String.fromCharCode expression selected its call or function-value form and complete private helper sequence before target syntax."
			})
		];
	}

	/** Records the private helpers selected by one `String.fromCharCode` expression. */
	public function recordStringFromCharCode(decision:OcamlStringFromCharCodeDecision):Void {
		for (requirement in requirementsForStringFromCharCode(decision))
			record(requirement);
	}

	/** Returns the HxString reason selected by one String equality expression. */
	public static function requirementsForStringEquality(decision:OcamlStringEqualityDecision):Array<OcamlRuntimeRequirement> {
		OcamlStringEqualityPlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: STRING_EQUALITY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.leftSemanticTypeId
					+ " "
					+ (decision.kind : String)
					+ " "
					+ decision.rightSemanticTypeId},
				implementationFeature: "haxe-string-equality-v1",
				rootModules: OcamlStringEqualityPlan.rootModules(decision),
				profileEligibility: decision.profileEligibility,
				explanation: "The final typed String comparison selected the null-safe equality helper before target syntax. Inequality applies target-native Boolean negation after the checked call."
			})
		];
	}

	/** Records the private helper selected by one String equality expression. */
	public function recordStringEquality(decision:OcamlStringEqualityDecision):Void {
		for (requirement in requirementsForStringEquality(decision))
			record(requirement);
	}

	/** Returns the direct runtime reasons selected by one standard String method. */
	public static function requirementsForStringMethod(decision:OcamlStringMethodDecision):Array<OcamlRuntimeRequirement> {
		OcamlStringMethodPlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: STRING_METHOD,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.receiverSemanticTypeId
					+ "."
					+ (decision.operation : String)
					+ "("
					+ decision.argumentSemanticTypeIds.join(",")
					+ ") -> "
					+ decision.resultSemanticTypeId},
				implementationFeature: "haxe-string-method-v1",
				rootModules: OcamlStringMethodPlan.rootModules(decision),
				profileEligibility: decision.profileEligibility,
				explanation: "The final typed direct String call selected its method helper, optional-index behavior, result carrier, and receiver-first evaluation schedule before target syntax."
			})
		];
	}

	/** Records the private helpers selected by one direct standard String call. */
	public function recordStringMethod(decision:OcamlStringMethodDecision):Void {
		for (requirement in requirementsForStringMethod(decision))
			record(requirement);
	}

	/** Returns the direct runtime reason selected by one standard String field read. */
	public static function requirementsForStringField(decision:OcamlStringFieldDecision):Array<OcamlRuntimeRequirement> {
		OcamlStringFieldPlan.requireDecision(decision);
		return [
			normalize({
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: STRING_FIELD,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.receiverSemanticTypeId
					+ "."
					+ decision.fieldName
					+ " -> "
					+ decision.resultSemanticTypeId},
				implementationFeature: "haxe-string-field-v1",
				rootModules: ["HxString"],
				profileEligibility: decision.profileEligibility,
				explanation: "The final typed String.length field read selected one private length helper and a receiver-first evaluation schedule before target syntax."
			})
		];
	}

	/** Records the private helper selected by one standard String field read. */
	public function recordStringField(decision:OcamlStringFieldDecision):Void {
		for (requirement in requirementsForStringField(decision))
			record(requirement);
	}

	/**
		Returns the runtime reason selected by one direct represented array literal.

		The producer already fixes allocation, source-order element evaluation, and
		one store per element. This record connects that source decision to the
		`HxArray` implementation before target syntax creates either private name.
	**/
	public static function requirementsForArrayLiteralProducer(decision:OcamlArrayLiteralProducerDecision):Array<OcamlRuntimeRequirement> {
		OcamlArrayLiteralProducerContract.requireDecision(decision);
		final requirementId = OcamlArrayLiteralProducerContract.runtimeRequirementIdFor(decision.id);
		if (decision.runtimeRequirementIds.length != 1 || decision.runtimeRequirementIds[0] != requirementId)
			throw 'Array literal producer "${decision.id}" has no exact runtime requirement.';
		return [
			normalize({
				id: requirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: ARRAY_LITERAL_CONSTRUCTION,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.arraySemanticTypeId
				},
				implementationFeature: "haxe-array-literal-construction-v1",
				rootModules: ["HxArray"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed direct array literal uses HxArray to allocate one mutable Haxe array and append each evaluated element exactly once in source order."
			})
		];
	}

	/** Records the runtime dependency selected by one direct represented array literal. */
	public function recordArrayLiteralProducer(decision:OcamlArrayLiteralProducerDecision):Void {
		for (requirement in requirementsForArrayLiteralProducer(decision))
			record(requirement);
	}

	/** Returns the runtime reason selected by one standard Array bracket read. */
	public static function requirementsForArrayRead(decision:OcamlArrayReadDecision):Array<OcamlRuntimeRequirement> {
		OcamlArrayReadContract.requireDecision(decision);
		return [
			normalize({
				id: OcamlArrayReadContract.runtimeRequirementId(decision.id),
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: OcamlArrayReadContract.RUNTIME_CAPABILITY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.receiverSemanticTypeId
				},
				implementationFeature: "haxe-array-v1",
				rootModules: ["HxArray"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed Array bracket read evaluates its receiver before its Int index and then reads the selected element once through HxArray."
			})
		];
	}

	/** Records the runtime dependency selected by one standard Array bracket read. */
	public function recordArrayRead(decision:OcamlArrayReadDecision):Void {
		for (requirement in requirementsForArrayRead(decision))
			record(requirement);
	}

	/** Returns the runtime reason selected by one non-Array compatibility read. */
	public static function requirementsForDynamicBracketRead(decision:OcamlDynamicBracketReadDecision):Array<OcamlRuntimeRequirement> {
		OcamlDynamicBracketReadContract.requireDecision(decision);
		return [
			normalize({
				id: OcamlDynamicBracketReadContract.runtimeRequirementId(decision.id),
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: OcamlDynamicBracketReadContract.RUNTIME_CAPABILITY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: decision.receiverSemanticTypeId
				},
				implementationFeature: "haxe-array-v1",
				rootModules: ["HxArray"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed compatibility read preserves a numeric-style bracket access on a non-Array value through HxArray without weakening standard Array proof."
			})
		];
	}

	/** Records the runtime dependency selected by one non-Array compatibility read. */
	public function recordDynamicBracketRead(decision:OcamlDynamicBracketReadDecision):Void {
		for (requirement in requirementsForDynamicBracketRead(decision))
			record(requirement);
	}

	#if macro
	/**
		Returns the runtime reasons selected by one complete Haxe catch chain.

		The catch plan already fixes private-control propagation, the Haxe exception
		input, and unmatched rethrow behavior. The first record connects that
		decision to `HxRuntime`. An enum clause adds its own `HxEnum` payload-recovery
		record. Neither reason is inferred from the generated OCaml pattern or call.
	**/
	public static function requirementsForCatchChain(chain:OcamlCatchChainDecision):Array<OcamlRuntimeRequirement> {
		OcamlControlPlan.requireCatchChain(chain);
		final requirements = [
			normalize({
				id: OcamlCatchRuntimeUseContract.requirementId(chain),
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: chain.id,
				source: chain.source,
				semanticCapability: chain.runtimeCapabilityId,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: chain.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "haxe.Exception"
				},
				implementationFeature: "haxe-typed-catch-signal-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: chain.profileEligibility,
				explanation: "The sealed Haxe catch chain propagates compiler-owned return and loop signals, receives one typed Haxe exception signal, and rethrows the same payload and runtime tags when no source catch clause matches."
			})
		];
		for (clause in chain.clauses) {
			if (OcamlControlPlan.isAdmittedEnumCatchClause(clause))
				requirements.push(normalize(OcamlEnumRuntimeRequirementRecorder.catchRequirement(chain, clause)));
		}
		return requirements;
	}

	/** Records the runtime dependency selected by one complete Haxe catch chain. */
	public function recordCatchChain(chain:OcamlCatchChainDecision):Void {
		for (requirement in requirementsForCatchChain(chain))
			record(requirement);
	}

	/** Returns the exact HxRuntime requirement selected by one sealed early return. */
	public static function requirementsForReturnDecision(decision:OcamlControlDecision):Array<OcamlRuntimeRequirement> {
		final plan = OcamlReturnRuntimeUseContract.forDecision(decision);
		final subjectType = decision.payload == null ? "Void" : decision.payload.outputSemanticTypeId;
		final implementation = switch (decision.mechanism) {
			case RuntimeReturnSignal: {
					feature: "haxe-function-return-signal-v1",
					explanation: "The sealed value-bearing return raises one private signal, and its owning Haxe function boundary matches that same signal to recover the already-selected result carrier."
				};
			case RuntimeVoidReturnSignal: {
					feature: "haxe-function-void-return-signal-v1",
					explanation: "The sealed payloadless return raises one private signal, and its owning effect-only Haxe Void function boundary matches that same signal to exit early."
				};
			case _: throw 'Return decision "${decision.id}" has no supported runtime signal.';
		};
		return [
			normalize({
				id: plan.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: decision.runtimeCapabilityId,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: subjectType
				},
				implementationFeature: implementation.feature,
				rootModules: ["HxRuntime"],
				profileEligibility: decision.profileEligibility,
				explanation: implementation.explanation
			})
		];
	}

	/** Records the private signal requirement owned by one sealed early return. */
	public function recordReturnDecision(decision:OcamlControlDecision):Void {
		for (requirement in requirementsForReturnDecision(decision))
			record(requirement);
	}

	/** Returns the exact runtime-module requirement selected by one sealed Haxe throw. */
	public static function requirementsForThrowDecision(decision:OcamlControlDecision):Array<OcamlRuntimeRequirement> {
		final plan = OcamlThrowRuntimeUseContract.forDecision(decision);
		final payload = decision.payload;
		if (payload == null)
			throw 'Throw decision "${decision.id}" has no sealed payload.';
		return [
			normalize({
				id: plan.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: decision.runtimeCapabilityId,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: payload.inputSemanticTypeId
				},
				implementationFeature: "haxe-typed-throw-v1",
				rootModules: OcamlThrowRuntimeUseContract.rootModules(plan),
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed Haxe throw sends one represented source value and its preselected runtime tags through the compiler-owned exception channel."
			})
		];
	}

	/** Records the private runtime calls required by one sealed Haxe throw. */
	public function recordThrowDecision(decision:OcamlControlDecision):Void {
		for (requirement in requirementsForThrowDecision(decision))
			record(requirement);
	}

	/** Returns the pattern requirements owned by one sealed lexical loop. */
	public static function requirementsForLoopTarget(target:OcamlControlLoopTarget, decisions:Array<OcamlControlDecision>):Array<OcamlRuntimeRequirement> {
		final plan = OcamlLoopRuntimeUseContract.forTarget(target, decisions);
		return plan.runtimeRequirementIds.map(requirementId -> {
			final isBreak = requirementId == OcamlLoopRuntimeUseContract.targetRequirementId(target, OcamlControlTransferKind.Break);
			final kind = isBreak ? OcamlControlTransferKind.Break : OcamlControlTransferKind.Continue;
			normalize({
				id: requirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: target.id,
				source: target.source,
				semanticCapability: OcamlLoopRuntimeUseContract.capabilityId(kind),
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: target.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Void"
				},
				implementationFeature: isBreak ? "haxe-loop-break-boundary-v1" : "haxe-loop-continue-boundary-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: isBreak ? "The sealed lexical loop catches its private break signal once at the exact target boundary." : "The sealed lexical loop catches its private continue signal once before evaluating the next condition."
			});
		});
	}

	/** Returns the signal requirement owned by one sealed break or continue. */
	public static function requirementsForLoopDecision(decision:OcamlControlDecision):Array<OcamlRuntimeRequirement> {
		final plan = OcamlLoopRuntimeUseContract.forDecision(decision);
		return [
			normalize({
				id: plan.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: decision.runtimeCapabilityId,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Void"
				},
				implementationFeature: decision.kind == OcamlControlTransferKind.Break ? "haxe-loop-break-signal-v1" : "haxe-loop-continue-signal-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed source loop transfer raises its exact private signal for the already-selected lexical target."
			})
		];
	}

	/** Records one loop boundary and each transfer that can reach it. */
	public function recordLoopTarget(target:OcamlControlLoopTarget, decisions:Array<OcamlControlDecision>):Void {
		for (requirement in requirementsForLoopTarget(target, decisions))
			record(requirement);
		for (decision in decisions)
			for (requirement in requirementsForLoopDecision(decision))
				record(requirement);
	}
	#end

	/**
		Returns the closed runtime requirements implied by one sealed program
		representation.

		Exact Haxe `String` uses the canonical null value owned by `HxString` in
		every selected domain. Exact `Null<Int>` and `Null<Bool>` field decisions
		use the canonical `HxRuntime` null value for their implicit initializer.
		Carrier-only local decisions do not claim that field default.
	**/
	public static function requirementsForRepresentationDecision(decision:OcamlRepresentationDecision):Array<OcamlRuntimeRequirement> {
		if (decision == null)
			throw "OCaml runtime requirement representation decision must not be null.";
		final selectsNullablePrimitiveFieldDefault = (decision.domain == OcamlRepresentationDomain.InstanceField
			|| decision.domain == OcamlRepresentationDomain.StaticField)
			&& (decision.boxingPolicy == OcamlRepresentationBoxingPolicy.NullablePrimitiveCarrier
				|| decision.proof.id == "nullable-int-obj-carrier-v2"
				|| decision.proof.id == "nullable-bool-obj-carrier-v2");
		if (selectsNullablePrimitiveFieldDefault) {
			final exactSemantic = decision.semanticTypeId == "Null<Int>" || decision.semanticTypeId == "Null<Bool>";
			final expectedProof = decision.semanticTypeId == "Null<Int>" ? "nullable-int-obj-carrier-v2" : "nullable-bool-obj-carrier-v2";
			if (!exactSemantic
				|| decision.carrierTypeId != "Obj.t"
				|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
				|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.NullablePrimitiveCarrier
				|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel
				|| decision.proof.id != expectedProof) {
				throw 'Representation decision "${decision.id}" does not match the sealed nullable primitive field-default contract.';
			}
			return [
				normalize({
					id: decision.id + ":runtime:" + NULLABLE_PRIMITIVE_FIELD_DEFAULT,
					sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
					sourceId: decision.id + "@" + decision.revision,
					source: {
						file: "compiler-decision/representation/" + decision.domain,
						min: 0,
						max: 0
					},
					semanticCapability: NULLABLE_PRIMITIVE_FIELD_DEFAULT,
					cause: OcamlRuntimeRequirementCause.RepresentationDecision,
					decisionId: decision.id,
					subject: {
						kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
						id: decision.semanticTypeId
					},
					implementationFeature: "haxe-nullable-primitive-field-default-v1",
					rootModules: ["HxRuntime"],
					profileEligibility: decision.profileEligibility,
					explanation: 'The sealed ${decision.semanticTypeId} field representation starts field storage at Haxe null through the canonical HxRuntime.hx_null value before any explicit initializer runs; this requirement owns no other nullable carrier crossing.'
				})
			];
		}
		final selectsExactStringSentinel = decision.boxingPolicy == OcamlRepresentationBoxingPolicy.NullableStringCarrier
			|| decision.proof.id == "nullable-string-runtime-sentinel-carrier-v1"
			|| decision.proof.id == "nullable-string-array-element-carrier-v1";
		if (!selectsExactStringSentinel)
			return [];
		if (decision.semanticTypeId != "String"
			|| decision.carrierTypeId != "string"
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.NullableStringCarrier
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel
			|| (decision.proof.id != "nullable-string-runtime-sentinel-carrier-v1"
				&& decision.proof.id != "nullable-string-array-element-carrier-v1")) {
			throw 'Representation decision "${decision.id}" does not match the sealed exact String null-sentinel contract.';
		}
		return [
			normalize({
				id: decision.id + ":runtime:" + STRING_NULL_SENTINEL,
				sourceKind: OcamlRuntimeRequirementSourceKind.RepresentationDecision,
				sourceId: decision.id + "@" + decision.revision,
				source: {
					file: "compiler-decision/representation/" + decision.domain,
					min: 0,
					max: 0
				},
				semanticCapability: STRING_NULL_SENTINEL,
				cause: OcamlRuntimeRequirementCause.RepresentationDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "String"
				},
				implementationFeature: "haxe-string-null-sentinel-v1",
				rootModules: ["HxString"],
				profileEligibility: decision.profileEligibility,
				explanation: "The sealed exact Haxe String carrier uses HxString.hx_null_string to preserve the canonical Haxe null sentinel; this requirement does not claim ownership of other HxString operations."
			})
		];
	}

	/** Records every runtime dependency implied by one sealed representation. **/
	public function recordRepresentationDecision(decision:OcamlRepresentationDecision):Void {
		for (requirement in requirementsForRepresentationDecision(decision))
			record(requirement);
	}

	/** Records one helper required by compiler-generated output or packaging policy. **/
	public function recordCompilerInfrastructure(capability:String):Void {
		record(requirementForCompilerInfrastructure(capability));
	}

	/** Builds the exact immutable requirement used by generated text authority. */
	public static function requirementForCompilerInfrastructure(capability:String):OcamlRuntimeRequirement {
		final implementation = compilerInfrastructureImplementation(capability);
		return normalize({
			id: implementation.id,
			sourceKind: OcamlRuntimeRequirementSourceKind.CompilerInfrastructure,
			sourceId: implementation.sourceId,
			source: {file: implementation.sourceFile, min: 0, max: 0},
			semanticCapability: capability,
			cause: OcamlRuntimeRequirementCause.CompilerInfrastructure,
			decisionId: implementation.decisionId,
			subject: {
				kind: implementation.subjectKind,
				id: implementation.subjectId
			},
			implementationFeature: implementation.feature,
			rootModules: [implementation.module],
			profileEligibility: capability == HXHX_BACKEND_PLUGIN_HOST ? ["portable"] : ["metal", "portable"],
			explanation: implementation.explanation
		});
	}

	/**
		Records one checked compatibility-runtime need declared by a typed native
		extern boundary.

		The capability selects the runtime implementation. The resolved native
		symbol is checked independently so a misleading declaration cannot make the
		report name a helper that the generated call does not use.
	**/
	public function recordNativeBoundary(capability:String, boundaryId:String, source:OcamlLoweredSourceSpan, nativeSymbol:String):Void {
		final implementation = nativeBoundaryImplementation(capability);
		final stableBoundaryId = required(boundaryId, "native boundary identity");
		final stableNativeSymbol = required(nativeSymbol, 'native symbol for boundary "$stableBoundaryId"');
		final nativeRoot = stableNativeSymbol.split(".")[0];
		if (nativeRoot != implementation.module)
			throw 'Native runtime capability "$capability" requires "${implementation.module}", but boundary "$stableBoundaryId" resolves to "$stableNativeSymbol".';
		record({
			id: "native:" + stableBoundaryId + ":runtime:" + capability,
			sourceKind: OcamlRuntimeRequirementSourceKind.NativeBoundary,
			sourceId: "haxe-declaration:" + stableBoundaryId,
			source: source,
			semanticCapability: capability,
			cause: OcamlRuntimeRequirementCause.NativeBoundary,
			decisionId: "native-boundary:" + stableBoundaryId,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.NativeBoundary,
				id: stableBoundaryId + " -> " + stableNativeSymbol
			},
			implementationFeature: implementation.feature,
			rootModules: [implementation.module],
			profileEligibility: ["metal", "portable"],
			explanation: implementation.explanation
		});
	}

	/** Returns immutable records in stable identity order. **/
	public function requirementsSorted():Array<OcamlRuntimeRequirement> {
		final out = [for (entry in byId) entry];
		out.sort((left, right) -> compareStrings(left.id, right.id));
		return out;
	}

	/**
		Returns the recorded requirements named by one sealed lowering plan.

		The returned order matches `ids`, so a caller can compare it with the
		plan that requested the runtime behavior. Missing or repeated IDs are an
		invariant failure: generation must not continue with incomplete authority.
	**/
	public function requirementsByIds(ids:Array<String>):Array<OcamlRuntimeRequirement> {
		if (ids == null)
			throw "OCaml runtime requirement lookup identities must be an array.";
		final out = new Array<OcamlRuntimeRequirement>();
		final seen:Map<String, Bool> = [];
		for (rawId in ids) {
			final id = required(rawId, "lookup identity");
			if (seen.exists(id))
				throw 'OCaml runtime requirement lookup repeats "$id".';
			final requirement = byId.get(id);
			if (requirement == null)
				throw 'OCaml runtime requirement lookup is missing "$id".';
			seen.set(id, true);
			out.push(requirement);
		}
		return out;
	}

	/** Returns the deduplicated runtime roots selected by recorded decisions. **/
	public function rootModulesSorted():Array<String> {
		final roots:Map<String, Bool> = [];
		for (entry in byId)
			for (moduleName in entry.rootModules)
				roots.set(moduleName, true);
		final out = [for (moduleName in roots.keys()) moduleName];
		out.sort(compareStrings);
		return out;
	}

	/** Computes a path-stable revision for reports and cache keys. **/
	public function revision():String {
		if (currentProgramRevision == null)
			throw "OCaml runtime requirement revision is unavailable before the program revision begins.";
		return "sha256:" + Sha256.encode(currentProgramRevision + "\n" + Json.stringify(requirementsSorted()));
	}

	static function placeImplementation(capability:String):{feature:String, module:String, explanation:String} {
		return switch (capability) {
			case INT32_ADD:
				{
					feature: "haxe-int32-arithmetic-v1",
					module: "HxInt",
					explanation: "Haxe Int addition has defined 32-bit overflow behavior, so generated OCaml uses the checked HxInt operation."
				};
			case ARRAY_ELEMENT_GET:
				{
					feature: "haxe-array-element-access-v1",
					module: "HxArray",
					explanation: "Reading a Haxe array element must preserve Haxe array bounds, storage, and identity behavior."
				};
			case ARRAY_ELEMENT_SET:
				{
					feature: "haxe-array-element-access-v1",
					module: "HxArray",
					explanation: "Writing a Haxe array element must update the original growable Haxe array using its checked storage contract."
				};
			case _:
				throw 'Unknown place runtime capability "$capability".';
		}
	}

	static function standardIMapImplementation(capability:String):{feature:String, module:String, explanation:String} {
		return switch (capability) {
			case HAXE_MAP:
				{
					feature: "haxe-map-v1",
					module: "HxMap",
					explanation: "The sealed standard IMap call uses HxMap for the exact String, Int, or object-identity storage operation selected from the final typed receiver."
				};
			case HAXE_ITERATOR:
				{
					feature: "haxe-iterator-v1",
					module: "HxIterator",
					explanation: "The sealed standard IMap call uses HxIterator to expose keys, values, pairs, or formatting traversal through Haxe's structural iterator contract."
				};
			case HAXE_ARRAY:
				{
					feature: "haxe-array-v1",
					module: "HxArray",
					explanation: "The sealed standard IMap text adapter uses HxArray to retain formatted entries in traversal order before joining them with the Haxe Map separator."
				};
			case HAXE_STRING_TEXT:
				{
					feature: "haxe-string-text-v1",
					module: "HxString",
					explanation: "The sealed standard IMap text adapter uses HxString to preserve the Haxe String null sentinel while converting an exact String key or value to displayed text."
				};
			case HAXE_DYNAMIC_TEXT:
				{
					feature: "haxe-dynamic-text-v1",
					module: "HxDynamic",
					explanation: "The sealed standard IMap text adapter uses HxDynamic for the typed fallback that formats a non-primitive key or value through registered Haxe runtime string behavior."
				};
			case OcamlStandardIMapCallContract.TYPE_RUNTIME_CAPABILITY:
				{
					feature: "haxe-type-reflection-v1",
					module: "HxType",
					explanation: "Every generated IMap dispatch record carries the exact haxe.IMap runtime type marker used by Haxe reflection."
				};
			case OcamlStandardIMapCallContract.CORE_RUNTIME_CAPABILITY:
				{
					feature: "haxe-runtime-core-v1",
					module: "HxRuntime",
					explanation: "The sealed IMap adapter converts an erased Boolean argument with the checked Haxe runtime carrier operation selected before syntax."
				};
			case _:
				throw 'Unknown standard IMap runtime capability "$capability".';
		}
	}

	static function normalize(requirement:OcamlRuntimeRequirement):OcamlRuntimeRequirement {
		if (requirement == null)
			throw "OCaml runtime requirement must not be null.";
		final id = required(requirement.id, "identity");
		final sourceId = required(requirement.sourceId, 'source identity for "$id"');
		final decisionId = required(requirement.decisionId, 'decision identity for "$id"');
		final semanticCapability = required(requirement.semanticCapability, 'semantic capability for "$id"');
		if (requirement.subject == null)
			throw 'OCaml runtime requirement "$id" must name its subject.';
		final subjectKind = validatedSubjectKind(requirement.subject.kind, requirement.sourceKind, id);
		final subjectId = required(requirement.subject.id, 'subject identity for "$id"');
		final implementationFeature = required(requirement.implementationFeature, 'implementation feature for "$id"');
		final explanation = required(requirement.explanation, 'explanation for "$id"');
		if (requirement.source == null || requirement.source.min < 0 || requirement.source.max < requirement.source.min)
			throw 'OCaml runtime requirement "$id" has an invalid source span.';
		final rootModules = normalizedTokens(requirement.rootModules, 'root modules for "$id"');
		if (rootModules.length == 0)
			throw 'OCaml runtime requirement "$id" must name at least one root module.';
		for (moduleName in rootModules)
			if (!~/^[A-Za-z][A-Za-z0-9_]*$/.match(moduleName))
				throw 'OCaml runtime requirement "$id" has invalid root module "$moduleName".';
		final profiles = normalizedTokens(requirement.profileEligibility, 'profiles for "$id"');
		if (profiles.length == 0)
			throw 'OCaml runtime requirement "$id" must name at least one eligible profile.';
		for (profile in profiles)
			if (profile != "metal" && profile != "portable")
				throw 'OCaml runtime requirement "$id" has unsupported profile "$profile".';
		return {
			id: id,
			sourceKind: requirement.sourceKind,
			sourceId: sourceId,
			source: {
				file: OcamlLoweredOrigin.normalizeSourcePath(requirement.source.file),
				min: requirement.source.min,
				max: requirement.source.max
			},
			semanticCapability: semanticCapability,
			cause: requirement.cause,
			decisionId: decisionId,
			subject: {
				kind: subjectKind,
				id: subjectId
			},
			implementationFeature: implementationFeature,
			rootModules: rootModules,
			profileEligibility: profiles,
			explanation: explanation
		};
	}

	static function compilerInfrastructureImplementation(capability:String):{
		id:String,
		sourceId:String,
		sourceFile:String,
		decisionId:String,
		subjectKind:OcamlRuntimeRequirementSubjectKind,
		subjectId:String,
		feature:String,
		module:String,
		explanation:String
	} {
		return switch (capability) {
			case CORE_RUNTIME:
				{
					id: "compiler:runtime-packaging:core",
					sourceId: "compiler-policy:runtime-packaging",
					sourceFile: "compiler-policy/runtime-packaging",
					decisionId: "compiler-runtime:select-core",
					subjectKind: OcamlRuntimeRequirementSubjectKind.CompilerPolicy,
					subjectId: "runtime-packaging",
					feature: "haxe-runtime-core-v1",
					module: "HxRuntime",
					explanation: "Every runtime-enabled project uses HxRuntime as the shared base for compatibility helpers and compiler control values."
				};
			case TYPE_REGISTRY:
				{
					id: "compiler:generated:HxTypeRegistry:type-registry",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-type-registry",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-type-reflection-registry-v1",
					module: "HxType",
					explanation: "The compiler-generated type registry uses HxType to register classes, enums, constructors, inheritance, and typed-catch identities."
				};
			case TYPE_REGISTRY_DYNAMIC_ARGS:
				{
					id: "compiler:generated:HxTypeRegistry:dynamic-arguments",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-reflection-constructor-arguments",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-reflection-constructor-arguments-v1",
					module: "HxArray",
					explanation: "Reflection constructors receive Haxe argument arrays, so the generated type registry uses the checked HxArray access contract."
				};
			case TYPE_REGISTRY_OPTIONAL_NULL:
				{
					id: "compiler:generated:HxTypeRegistry:optional-null",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-reflection-optional-null",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-reflection-optional-arguments-v1",
					module: "HxRuntime",
					explanation: "Missing optional reflection arguments use the target runtime representation of Haxe null."
				};
			case TYPE_REGISTRY_OPTIONAL_STRING_NULL:
				{
					id: "compiler:generated:HxTypeRegistry:optional-string-null",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-reflection-optional-string-null",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-reflection-optional-string-arguments-v1",
					module: "HxString",
					explanation: "Missing optional exact String reflection arguments use the checked HxString null sentinel."
				};
			case TYPE_REGISTRY_RUNTIME_UNBOX:
				{
					id: "compiler:generated:HxTypeRegistry:runtime-unbox",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:emit-reflection-boolean-unbox",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-reflection-boolean-argument-unboxing-v1",
					module: "HxRuntime",
					explanation: "Reflection constructors use the checked runtime conversion when a dynamically supplied argument must become a Haxe Bool."
				};
			case TYPE_REGISTRY_DYNAMIC_STRING:
				{
					id: "compiler:generated:HxTypeRegistry:dynamic-string",
					sourceId: "compiler-generated:HxTypeRegistry",
					sourceFile: "compiler-generated/HxTypeRegistry.ml",
					decisionId: "compiler-runtime:register-dynamic-stringifiers",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "HxTypeRegistry",
					feature: "haxe-dynamic-class-string-v1",
					module: "HxDynamic",
					explanation: "Generated classes with an exact zero-argument String toString method register one typed adapter with the shared Dynamic runtime."
				};
			case HXHX_BACKEND_PLUGIN_HOST:
				{
					id: "compiler:generated:DunePluginEntry:backend-provider-registration",
					sourceId: "compiler-generated:DunePluginEntry",
					sourceFile: "compiler-generated/DunePluginEntry.ml",
					decisionId: "compiler-runtime:emit-backend-plugin-registration",
					subjectKind: OcamlRuntimeRequirementSubjectKind.GeneratedModule,
					subjectId: "DunePluginEntry",
					feature: "hxhx-backend-plugin-host-registration-v1",
					module: "HxHxBackendPluginHost",
					explanation: "A generated native backend-plugin entry registers its declared provider type with the hxhx host when OCaml loads the plugin."
				};
			case _:
				throw 'Unknown compiler runtime capability "$capability".';
		}
	}

	static function nativeBoundaryImplementation(capability:String):{feature:String, module:String, explanation:String} {
		return switch (capability) {
			case HAXE_STANDARD_IO:
				{
					feature: "haxe-standard-io-v1",
					module: "HxStdio",
					explanation: "The typed OCaml standard-I/O facade uses HxStdio to preserve Haxe stream reads, writes, end-of-file behavior, and flushing."
				};
			case HAXE_STACK_TRACES:
				{
					feature: "haxe-stack-traces-v1",
					module: "HxBacktrace",
					explanation: "The typed Haxe stack-trace facades use HxBacktrace to capture OCaml call and exception frames as Haxe arrays of strings."
				};
			case HAXE_FLOAT_BIT_CONVERSIONS:
				{
					feature: "haxe-float-bit-conversions-v1",
					module: "HxFPHelper",
					explanation: "The typed Haxe floating-point facade uses HxFPHelper to convert Float values to and from their exact 32-bit or 64-bit representations."
				};
			case HAXE_PROCESS:
				{
					feature: "haxe-process-v1",
					module: "HxProcess",
					explanation: "The typed Haxe process facade uses HxProcess to spawn and control child processes and to exchange bytes, lines, and strings through their standard streams."
				};
			case HAXE_FILE:
				{
					feature: "haxe-file-v1",
					module: "HxFile",
					explanation: "The typed Haxe file facade uses HxFile to read, write, and copy whole file contents with exact String and BytesData carriers."
				};
			case HAXE_FILE_STREAM:
				{
					feature: "haxe-file-stream-v1",
					module: "HxFileStream",
					explanation: "The typed Haxe file-stream facades use HxFileStream to open, read, write, seek, flush, query, and close file channels."
				};
			case HAXE_THREAD:
				{
					feature: "haxe-thread-v1",
					module: "HxThread",
					explanation: "The typed Haxe thread facades use HxThread for synchronization, message passing, deques, thread-local storage, and event-loop attachment."
				};
			case HAXE_FILE_SYSTEM:
				{
					feature: "haxe-file-system-v1",
					module: "HxFileSystem",
					explanation: "The typed Haxe filesystem facade uses HxFileSystem for path inspection, directory operations, metadata, rename, and deletion."
				};
			case HAXE_SYSTEM:
				{
					feature: "haxe-system-v1",
					module: "HxSys",
					explanation: "Typed Haxe Sys declarations use HxSys for process arguments, environment access, command execution, timing, working-directory operations, host identity, program paths, process exit, and character input."
				};
			case HAXE_MAP:
				{
					feature: "haxe-map-v1",
					module: "HxMap",
					explanation: "Typed Haxe StringMap, IntMap, and ObjectMap declarations use HxMap for checked mutable storage with the selected string, integer, or identity-key representation."
				};
			case HAXE_ITERATOR:
				{
					feature: "haxe-iterator-v1",
					module: "HxIterator",
					explanation: "Typed Haxe iterator-producing declarations use HxIterator to preserve the structural hasNext and next carrier over a target runtime array."
				};
			case _:
				throw 'Unknown native runtime capability "$capability".';
		}
	}

	static function validatedSubjectKind(kind:OcamlRuntimeRequirementSubjectKind, sourceKind:OcamlRuntimeRequirementSourceKind,
			id:String):OcamlRuntimeRequirementSubjectKind {
		final valid = switch (sourceKind) {
			case HaxeExpression: kind == OcamlRuntimeRequirementSubjectKind.HaxeType;
			case RepresentationDecision: kind == OcamlRuntimeRequirementSubjectKind.HaxeType;
			case CompilerInfrastructure: kind == OcamlRuntimeRequirementSubjectKind.GeneratedModule || kind == OcamlRuntimeRequirementSubjectKind.CompilerPolicy;
			case Configuration: kind == OcamlRuntimeRequirementSubjectKind.CompilerPolicy;
			case NativeBoundary: kind == OcamlRuntimeRequirementSubjectKind.NativeBoundary;
			case RawBoundary: kind == OcamlRuntimeRequirementSubjectKind.RawBoundary;
		};
		if (!valid)
			throw 'OCaml runtime requirement "$id" has subject kind "$kind" that does not match source kind "$sourceKind".';
		return kind;
	}

	static function normalizedTokens(values:Array<String>, label:String):Array<String> {
		if (values == null)
			throw 'OCaml runtime requirement $label must be an array.';
		final out = new Array<String>();
		final seen:Map<String, Bool> = [];
		for (raw in values) {
			final value = required(raw, label);
			if (seen.exists(value))
				throw 'OCaml runtime requirement $label repeats "$value".';
			seen.set(value, true);
			out.push(value);
		}
		out.sort(compareStrings);
		return out;
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : value.trim();
		if (normalized.length == 0)
			throw 'OCaml runtime requirement $label must not be empty.';
		return normalized;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
