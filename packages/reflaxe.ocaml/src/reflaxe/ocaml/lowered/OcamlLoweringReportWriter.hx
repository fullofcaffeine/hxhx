package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementDecision;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionContract;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionFamily;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionSnapshot;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionStatus;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary.OcamlFunctionResultBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReportEntry;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationRecord;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentedArrayDescriptor;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlInt64RepresentationModel.OcamlInt64RepresentationContract;
import reflaxe.ocaml.lowered.OcamlIMapInterfacePlan;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceCallDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionDecision;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageReportEntry;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldContract;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.runtimegen.OcamlAnonymousStructureRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlStructuralFieldRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlEnumRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/**
	Writes the deterministic report for sealed representation and lowering facts.

	The report exposes place operations, local carrier crossings, the admitted
	unsafe-operation proofs that own those crossings, static storage, and their
	runtime requirements. It never infers those facts from generated OCaml text.
**/
class OcamlLoweringReportWriter {
	public static inline final FILE_NAME = "ocaml_lowering_report.json";
	public static inline final SCHEMA_VERSION = 64;
	public static inline final REPRESENTATION_SCOPE = "exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15";

	static function validateNominalRepresentation(decision:OcamlRepresentationDecision):Void {
		final nominalCount = (decision.nominalTargetModuleName == null ? 0 : 1) + (decision.nominalTargetTypeName == null ? 0 : 1)
			+ (decision.nominalLayoutRevision == null ? 0 : 1);
		final isNominal = decision.boxingPolicy == OcamlRepresentationBoxingPolicy.NullableNominalRecordCarrier
			|| decision.boxingPolicy == OcamlRepresentationBoxingPolicy.DirectNominalValueCarrier;
		if (isNominal != (nominalCount == 3))
			throw 'Program representation "${decision.id}" has incomplete or unexpected nominal carrier metadata.';
		if (!isNominal)
			return;
		if (decision.nominalTargetModuleName.length == 0
			|| decision.nominalTargetTypeName.length == 0
			|| decision.carrierTypeId != decision.nominalTargetTypeName
			|| !StringTools.startsWith(decision.nominalLayoutRevision, "sha256:")) {
			throw 'Program representation "${decision.id}" does not match its sealed nominal carrier layout.';
		}
		if (decision.boxingPolicy == OcamlRepresentationBoxingPolicy.DirectNominalValueCarrier) {
			if (decision.semanticTypeId != OcamlInt64RepresentationContract.SEMANTIC_TYPE_ID
				|| decision.nominalTargetModuleName != OcamlInt64RepresentationContract.TARGET_MODULE_NAME
				|| decision.nominalTargetTypeName != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
				|| decision.nominalLayoutRevision != OcamlInt64RepresentationContract.LAYOUT_REVISION
				|| decision.proof.id != OcamlInt64RepresentationContract.PROOF_ID
				|| decision.domain != OcamlRepresentationDomain.InternalValue
				|| decision.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding) {
				throw 'Program representation "${decision.id}" does not match the sealed exact Int64 nominal value carrier.';
			}
			return;
		}
		if (decision.proof.id != "whole-program-monomorphic-nominal-record-v1:" + decision.nominalLayoutRevision) {
			throw 'Program representation "${decision.id}" does not match its sealed monomorphic-class proof.';
		}
		final expectedStoragePolicy = switch (decision.domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case _:
				throw 'Program representation "${decision.id}" selects unsupported nominal carrier domain ${decision.domain}.';
		};
		if (decision.storageMutationPolicy != expectedStoragePolicy) {
			throw 'Program representation "${decision.id}" selects ${decision.storageMutationPolicy} storage for nominal carrier domain ${decision.domain}, expected $expectedStoragePolicy.';
		}
	}

	static function requireRepresentation(byId:Map<String, OcamlRepresentationDecision>, id:String, semanticTypeId:String, carrierTypeId:String,
			domain:OcamlRepresentationDomain, owner:String, ?expectedRevision:String):Void {
		final decision = byId.get(id);
		if (decision == null)
			throw '$owner refers to missing program representation "$id".';
		if (decision.semanticTypeId != semanticTypeId
			|| decision.carrierTypeId != carrierTypeId
			|| decision.domain != domain
			|| (expectedRevision != null && decision.revision != expectedRevision)) {
			throw '$owner expects $semanticTypeId -> $carrierTypeId in $domain${expectedRevision == null ? "" : " at " + expectedRevision}, but representation ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain} at ${decision.revision}.';
		}
	}

	static function requireCallValue(byId:Map<String, OcamlRepresentationDecision>, value:OcamlCallValuePlan, owner:String):Void {
		requireRepresentation(byId, value.inputRepresentationId, value.inputSemanticTypeId, value.inputCarrierTypeId, OcamlRepresentationDomain.InternalValue,
			owner + " input");
		requireRepresentation(byId, value.outputRepresentationId, value.outputSemanticTypeId, value.outputCarrierTypeId,
			OcamlRepresentationDomain.InternalValue, owner + " output");
	}

	static function sameOptionalBoundary(left:Null<OcamlCallValuePlan>, right:Null<OcamlCallValuePlan>):Bool {
		if (left == null || right == null)
			return left == null && right == null;
		return OcamlCallPlan.sameCallableBoundary(left, right, false);
	}

	public static function write(outputDirectory:String, entries:Array<OcamlLoweredPlaceReportEntry>, requirements:Array<OcamlRuntimeRequirement>,
			representations:Array<OcamlRepresentationDecision>, representedArrays:Array<OcamlRepresentedArrayDescriptor>,
			arrayLiteralProducers:Array<OcamlArrayLiteralProducerDecision>, anonymousStructures:Array<OcamlAnonymousStructureDecision>,
			anonymousOperations:Array<OcamlAnonymousStructureOperationDecision>, structuralFields:Array<OcamlStructuralFieldDecision>,
			localConversions:Array<OcamlLocalConversionDecision>, containerElementRequiredConversionIds:Array<String>,
			containerElementConversions:Array<OcamlContainerElementDecision>, unsafeOperations:Array<OcamlUnsafeOperationRecord>,
			iMapInterfaceConversions:Array<OcamlIMapInterfaceConversionDecision>, iMapInterfaceCalls:Array<OcamlIMapInterfaceCallDecision>,
			calls:Array<OcamlCallDecision>, callableBoundaries:Array<OcamlCallableBoundaryPlan>,
			functionResultBoundaries:Array<OcamlFunctionResultBoundaryPlan>, controls:Array<OcamlControlDecision>,
			controlLoopTargets:Array<OcamlControlLoopTarget>, controlCatchChains:Array<OcamlCatchChainDecision>,
			controlAdmissions:Array<OcamlControlAdmissionSnapshot>, staticStorage:Array<OcamlStaticStorageReportEntry>, staticStorageRevision:String,
			artifacts:OcamlArtifactManifestBuilder):Void {
		final sorted = entries.copy();
		sorted.sort((left, right) -> left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
		final sortedRepresentations = representations.copy();
		sortedRepresentations.sort((left, right) -> left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
		final representationById:Map<String, OcamlRepresentationDecision> = [];
		for (representation in sortedRepresentations) {
			if (representationById.exists(representation.id))
				throw 'Program representation identity "${representation.id}" occurs more than once.';
			validateNominalRepresentation(representation);
			representationById.set(representation.id, representation);
		}
		final sortedRepresentedArrays = representedArrays.copy();
		sortedRepresentedArrays.sort((left, right) -> Reflect.compare(left.id, right.id));
		final representedArrayById:Map<String, OcamlRepresentedArrayDescriptor> = [];
		for (descriptor in sortedRepresentedArrays) {
			if (representedArrayById.exists(descriptor.id))
				throw 'Represented-array descriptor identity "${descriptor.id}" occurs more than once.';
			final element = representationById.get(descriptor.elementRepresentationId);
			if (element == null)
				throw 'Represented-array descriptor "${descriptor.id}" refers to missing element representation "${descriptor.elementRepresentationId}".';
			OcamlRepresentationRegistry.validateRepresentedArrayDescriptor(descriptor, element, descriptor.programRevision);
			representedArrayById.set(descriptor.id, descriptor);
		}
		for (representation in sortedRepresentations) {
			final descriptorFieldCount = (representation.arrayDescriptorId == null ? 0 : 1) + (representation.arrayDescriptorRevision == null ? 0 : 1);
			if (descriptorFieldCount == 0)
				continue;
			if (descriptorFieldCount != 2)
				throw 'Program representation "${representation.id}" has incomplete represented-array metadata.';
			final descriptor = representedArrayById.get(representation.arrayDescriptorId);
			if (descriptor == null
				|| descriptor.revision != representation.arrayDescriptorRevision
				|| descriptor.programRevision != representation.programRevision
				|| descriptor.arraySemanticTypeId != representation.semanticTypeId
				|| descriptor.arrayCarrierTypeId != representation.carrierTypeId) {
				throw 'Program representation "${representation.id}" does not match ${representation.arrayDescriptorId}@${representation.arrayDescriptorRevision}.';
			}
		}
		final sortedArrayLiteralProducers = arrayLiteralProducers.copy();
		sortedArrayLiteralProducers.sort((left, right) -> Reflect.compare(left.id, right.id));
		final arrayLiteralProducerById:Map<String, OcamlArrayLiteralProducerDecision> = [];
		final arrayLiteralProducersByBinding:Map<String, Array<OcamlArrayLiteralProducerDecision>> = [];
		for (producer in sortedArrayLiteralProducers) {
			OcamlArrayLiteralProducerContract.requireDecision(producer);
			if (arrayLiteralProducerById.exists(producer.id))
				throw 'Array-literal producer identity "${producer.id}" occurs more than once.';
			requireRepresentation(representationById, producer.resultRepresentationId, producer.arraySemanticTypeId, producer.arrayCarrierTypeId,
				OcamlRepresentationDomain.InternalValue, 'Array-literal producer "${producer.id}" result', producer.resultRepresentationRevision);
			final descriptor = representedArrayById.get(producer.arrayDescriptorId);
			if (descriptor == null
				|| descriptor.revision != producer.arrayDescriptorRevision
				|| descriptor.programRevision != producer.programRevision
				|| descriptor.arraySemanticTypeId != producer.arraySemanticTypeId
				|| descriptor.arrayCarrierTypeId != producer.arrayCarrierTypeId
				|| descriptor.elementSemanticTypeId != producer.elementSemanticTypeId
				|| descriptor.elementCarrierTypeId != producer.elementCarrierTypeId
				|| descriptor.elementRepresentationId != producer.elementRepresentationId
				|| descriptor.elementRepresentationRevision != producer.elementRepresentationRevision) {
				throw 'Array-literal producer "${producer.id}" does not match its represented-array descriptor and representation leaves.';
			}
			final bindingKey = OcamlArrayLiteralProducerContract.bindingKey(producer.functionId, producer.programRevision, producer.bodyRevision,
				producer.pipelineRevision);
			final bindingProducers = arrayLiteralProducersByBinding.get(bindingKey);
			if (bindingProducers == null)
				arrayLiteralProducersByBinding.set(bindingKey, [producer]);
			else
				bindingProducers.push(producer);
			arrayLiteralProducerById.set(producer.id, producer);
		}
		final arrayLiteralProducerPlanRevisionByBinding:Map<String, String> = [];
		for (bindingKey => producers in arrayLiteralProducersByBinding)
			arrayLiteralProducerPlanRevisionByBinding.set(bindingKey, OcamlArrayLiteralProducerContract.planRevision(producers));
		final sortedAnonymousStructures = anonymousStructures.copy();
		sortedAnonymousStructures.sort((left, right) -> Reflect.compare(left.id, right.id));
		final anonymousStructureById:Map<String, OcamlAnonymousStructureDecision> = [];
		for (structure in sortedAnonymousStructures) {
			OcamlAnonymousStructureContract.requireStructure(structure);
			if (anonymousStructureById.exists(structure.id))
				throw 'Anonymous structure identity "${structure.id}" occurs more than once.';
			requireRepresentation(representationById, structure.representationId, structure.semanticTypeId, structure.carrierTypeId,
				OcamlRepresentationDomain.InternalValue, 'Anonymous structure "${structure.id}"', structure.representationRevision);
			for (field in structure.fields) {
				requireRepresentation(representationById, field.representationId, field.semanticTypeId, field.carrierTypeId,
					OcamlRepresentationDomain.InternalValue, 'Anonymous structure "${structure.id}" field "${field.name}"', field.representationRevision);
			}
			anonymousStructureById.set(structure.id, structure);
		}
		final sortedAnonymousOperations = anonymousOperations.copy();
		sortedAnonymousOperations.sort((left, right) -> Reflect.compare(left.id, right.id));
		final anonymousOperationIds:Map<String, Bool> = [];
		for (operation in sortedAnonymousOperations) {
			final structure = anonymousStructureById.get(operation.structureId);
			if (structure == null)
				throw 'Anonymous operation "${operation.id}" refers to missing structure "${operation.structureId}".';
			OcamlAnonymousStructureContract.requireOperation(operation, structure);
			if (anonymousOperationIds.exists(operation.id))
				throw 'Anonymous operation identity "${operation.id}" occurs more than once.';
			anonymousOperationIds.set(operation.id, true);
		}
		final sortedStructuralFields = structuralFields.copy();
		sortedStructuralFields.sort((left, right) -> Reflect.compare(left.id, right.id));
		final structuralFieldIds:Map<String, Bool> = [];
		for (decision in sortedStructuralFields) {
			OcamlStructuralFieldContract.require(decision);
			if (structuralFieldIds.exists(decision.id))
				throw 'Structural field decision identity "${decision.id}" occurs more than once.';
			structuralFieldIds.set(decision.id, true);
		}
		final sortedIMapInterfaceConversions = iMapInterfaceConversions.copy();
		sortedIMapInterfaceConversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		final iMapInterfaceConversionIds:Map<String, Bool> = [];
		for (conversion in sortedIMapInterfaceConversions) {
			OcamlIMapInterfacePlan.requireConversionDecision(conversion);
			if (iMapInterfaceConversionIds.exists(conversion.id))
				throw 'IMap interface conversion identity "${conversion.id}" occurs more than once.';
			iMapInterfaceConversionIds.set(conversion.id, true);
		}
		final sortedIMapInterfaceCalls = iMapInterfaceCalls.copy();
		sortedIMapInterfaceCalls.sort((left, right) -> Reflect.compare(left.id, right.id));
		final iMapInterfaceCallIds:Map<String, Bool> = [];
		for (call in sortedIMapInterfaceCalls) {
			OcamlIMapInterfacePlan.requireCallDecision(call);
			if (iMapInterfaceCallIds.exists(call.id))
				throw 'IMap interface call identity "${call.id}" occurs more than once.';
			iMapInterfaceCallIds.set(call.id, true);
		}
		for (entry in sorted) {
			final domain = switch (entry.place.kind) {
				case OcamlLoweredPlaceKind.InstanceField: OcamlRepresentationDomain.InstanceField;
				case OcamlLoweredPlaceKind.StaticField: OcamlRepresentationDomain.StaticField;
				case OcamlLoweredPlaceKind.ArrayElement: OcamlRepresentationDomain.ArrayElement;
			}
			requireRepresentation(representationById, entry.place.representationId, entry.place.semanticTypeId, entry.place.carrierTypeId, domain,
				'Lowered place plan "${entry.id}"');
			final indexRepresentationId = entry.place.indexRepresentationId;
			if (indexRepresentationId != null) {
				requireRepresentation(representationById, indexRepresentationId, entry.place.indexSemanticTypeId, entry.place.indexCarrierTypeId,
					OcamlRepresentationDomain.InternalValue, 'Lowered place plan "${entry.id}" index');
			}
			final receiverRepresentationId = entry.place.receiverRepresentationId;
			if (entry.place.kind == OcamlLoweredPlaceKind.ArrayElement) {
				if (receiverRepresentationId == null)
					throw 'Lowered array place plan "${entry.id}" has no receiver representation.';
				requireRepresentation(representationById, receiverRepresentationId, entry.place.receiverSemanticTypeId, entry.place.receiverCarrierTypeId,
					OcamlRepresentationDomain.InternalValue, 'Lowered place plan "${entry.id}" receiver');
			} else if (receiverRepresentationId != null && StringTools.startsWith(receiverRepresentationId, "representation:")) {
				requireRepresentation(representationById, receiverRepresentationId, entry.place.receiverSemanticTypeId, entry.place.receiverCarrierTypeId,
					OcamlRepresentationDomain.InternalValue, 'Lowered place plan "${entry.id}" receiver');
			}
		}
		final sortedStaticStorage = staticStorage.copy();
		sortedStaticStorage.sort((left, right) -> Reflect.compare(left.key, right.key));
		for (entry in sortedStaticStorage) {
			if (entry.representationId != null) {
				requireRepresentation(representationById, entry.representationId, entry.semanticTypeId, entry.carrierTypeId,
					OcamlRepresentationDomain.StaticField, 'Static storage plan "${entry.id}"');
			}
		}
		final sortedCalls = calls.copy();
		sortedCalls.sort((left, right) -> Reflect.compare(left.id, right.id));
		final sortedCallableBoundaries = callableBoundaries.copy();
		sortedCallableBoundaries.sort((left, right) -> Reflect.compare(left.calleeId, right.calleeId));
		final callableByCallee:Map<String, OcamlCallableBoundaryPlan> = [];
		final callableById:Map<String, OcamlCallableBoundaryPlan> = [];
		for (boundary in sortedCallableBoundaries) {
			OcamlCallPlan.requireCallableBoundary(boundary);
			if (callableByCallee.exists(boundary.calleeId) || callableById.exists(boundary.id))
				throw 'Callable boundary identity "${boundary.calleeId}" occurs more than once.';
			if (boundary.receiver != null)
				requireCallValue(representationById, boundary.receiver, 'Callable boundary "${boundary.id}" receiver');
			for (index in 0...boundary.arguments.length)
				requireCallValue(representationById, boundary.arguments[index], 'Callable boundary "${boundary.id}" argument $index');
			if (boundary.result != null)
				requireCallValue(representationById, boundary.result, 'Callable boundary "${boundary.id}" result');
			callableByCallee.set(boundary.calleeId, boundary);
			callableById.set(boundary.id, boundary);
		}
		final sortedFunctionResultBoundaries = functionResultBoundaries.map(OcamlFunctionResultBoundary.copy);
		sortedFunctionResultBoundaries.sort((left, right) -> Reflect.compare(left.id, right.id));
		final functionResultByFunction:Map<String, OcamlFunctionResultBoundaryPlan> = [];
		final functionResultIds:Map<String, Bool> = [];
		for (boundary in sortedFunctionResultBoundaries) {
			OcamlFunctionResultBoundary.require(boundary);
			if (functionResultIds.exists(boundary.id) || functionResultByFunction.exists(boundary.functionId))
				throw 'Function result boundary identity "${boundary.id}" or function "${boundary.functionId}" occurs more than once.';
			if (boundary.result != null)
				requireCallValue(representationById, boundary.result, 'Function result boundary "${boundary.id}" result');
			if (boundary.callableBoundaryId != null) {
				final callable = callableById.get(boundary.callableBoundaryId);
				if (callable == null)
					throw 'Function result boundary "${boundary.id}" refers to missing callable boundary "${boundary.callableBoundaryId}".';
				OcamlFunctionResultBoundary.requireCallableMatch(boundary, callable);
			}
			functionResultIds.set(boundary.id, true);
			functionResultByFunction.set(boundary.functionId, boundary);
		}
		for (call in sortedCalls) {
			OcamlCallPlan.requireCall(call);
			if (call.receiver != null)
				requireCallValue(representationById, call.receiver, 'Call "${call.id}" receiver');
			for (index in 0...call.arguments.length)
				requireCallValue(representationById, call.arguments[index], 'Call "${call.id}" argument $index');
			if (call.result != null)
				requireCallValue(representationById, call.result, 'Call "${call.id}" result');
			if (call.kind == OcamlCallKind.TypedFunctionValue
				|| call.kind == OcamlCallKind.StandardIMapMethod
				|| call.kind == OcamlCallKind.StructuralIteratorMethod)
				continue;
			final boundary = callableByCallee.get(call.calleeId);
			if (boundary == null)
				throw 'Call "${call.id}" refers to missing callable boundary "${call.calleeId}".';
			if (boundary.kind != call.kind
				|| boundary.sourceModuleId != call.sourceModuleId
				|| boundary.sourceTypeName != call.sourceTypeName
				|| boundary.sourceFieldName != call.sourceFieldName
				|| boundary.arguments.length != call.arguments.length
				|| !OcamlCallPlan.sameCallResult(call.resultKind, call.result, boundary.resultKind, boundary.result)
				|| !sameOptionalBoundary(call.receiver, boundary.receiver)) {
				throw 'Call "${call.id}" disagrees with callable boundary "${boundary.id}".';
			}
			for (index in 0...call.arguments.length) {
				if (!OcamlCallPlan.sameCallableBoundary(call.arguments[index], boundary.arguments[index], false))
					throw 'Call "${call.id}" argument $index disagrees with callable boundary "${boundary.id}".';
			}
		}
		final sortedControlAdmissions = controlAdmissions.map(OcamlControlAdmissionContract.copySnapshot);
		sortedControlAdmissions.sort((left, right) -> Reflect.compare(left.id, right.id));
		final controlAdmissionByFunction:Map<String, OcamlControlAdmissionSnapshot> = [];
		final controlAdmissionIds:Map<String, Bool> = [];
		for (admission in sortedControlAdmissions) {
			OcamlControlAdmissionContract.requireSnapshot(admission);
			if (controlAdmissionIds.exists(admission.id) || controlAdmissionByFunction.exists(admission.functionId))
				throw 'Control admission identity "${admission.id}" or function "${admission.functionId}" occurs more than once.';
			controlAdmissionIds.set(admission.id, true);
			controlAdmissionByFunction.set(admission.functionId, admission);
			final returnFamily = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Return);
			if (returnFamily.status == OcamlControlAdmissionStatus.Admitted
				&& returnFamily.occurrenceCount > 0
				&& admission.functionId.indexOf("|nested-function|") < 0
				&& !functionResultByFunction.exists(admission.functionId)) {
				throw 'Control admission "${admission.id}" admits return transfers without a function result boundary.';
			}
		}
		final sortedControlTargets = controlLoopTargets.copy();
		sortedControlTargets.sort((left, right) -> Reflect.compare(left.id, right.id));
		final controlTargetById:Map<String, OcamlControlLoopTarget> = [];
		for (target in sortedControlTargets) {
			OcamlControlPlan.requireLoopTarget(target);
			if (controlTargetById.exists(target.id))
				throw 'Control loop target identity "${target.id}" occurs more than once.';
			if (!controlAdmissionByFunction.exists(target.functionId))
				throw 'Control loop target "${target.id}" has no complete function-admission snapshot.';
			controlTargetById.set(target.id, target);
		}
		final sortedControls = controls.copy();
		sortedControls.sort((left, right) -> Reflect.compare(left.id, right.id));
		final controlById:Map<String, Bool> = [];
		for (control in sortedControls) {
			OcamlControlPlan.requireDecision(control);
			if (controlById.exists(control.id))
				throw 'Control decision identity "${control.id}" occurs more than once.';
			if (!controlAdmissionByFunction.exists(control.functionId))
				throw 'Control decision "${control.id}" has no complete function-admission snapshot.';
			controlById.set(control.id, true);
			final payload = control.payload;
			if (payload != null) {
				final literalProducerFieldCount = (payload.arrayLiteralProducerId == null ? 0 : 1) + (payload.arrayLiteralProducerPlanRevision == null ? 0 : 1);
				if (literalProducerFieldCount != 0 && literalProducerFieldCount != 2)
					throw 'Control decision "${control.id}" has an incomplete array-literal producer reference.';
				if (payload.representationRevision != null) {
					requireRepresentation(representationById, payload.inputRepresentationId, payload.inputSemanticTypeId, payload.inputCarrierTypeId,
						OcamlRepresentationDomain.InternalValue, 'Control decision "${control.id}" revision-bound input', payload.representationRevision);
				}
				if (payload.arrayDescriptorId != null) {
					final representation = representationById.get(payload.inputRepresentationId);
					final descriptor = representedArrayById.get(payload.arrayDescriptorId);
					if (representation == null
						|| descriptor == null
						|| payload.arrayDescriptorRevision != descriptor.revision
						|| representation.arrayDescriptorId != descriptor.id
						|| representation.arrayDescriptorRevision != descriptor.revision
						|| !OcamlControlPlan.isAdmittedRepresentedArrayThrowPayload(payload)) {
						throw 'Control decision "${control.id}" does not match its represented-array descriptor and representation revisions.';
					}
				}
				if (literalProducerFieldCount == 2) {
					final producerId:String = cast payload.arrayLiteralProducerId;
					final producer = arrayLiteralProducerById.get(producerId);
					final bindingKey = OcamlArrayLiteralProducerContract.bindingKey(control.functionId, control.programRevision, control.bodyRevision,
						control.pipelineRevision);
					final planRevision = arrayLiteralProducerPlanRevisionByBinding.get(bindingKey);
					if (producer == null
						|| planRevision == null
						|| payload.arrayLiteralProducerPlanRevision != planRevision
						|| producer.functionId != control.functionId
						|| producer.programRevision != control.programRevision
						|| producer.bodyRevision != control.bodyRevision
						|| producer.pipelineRevision != control.pipelineRevision
						|| producer.resultRepresentationId != payload.inputRepresentationId
						|| producer.resultRepresentationRevision != payload.representationRevision
						|| producer.arrayDescriptorId != payload.arrayDescriptorId
						|| producer.arrayDescriptorRevision != payload.arrayDescriptorRevision) {
						throw 'Control decision "${control.id}" does not consume its exact revision-bound array-literal producer.';
					}
				}
				if (payload.inputSemanticTypeId == "Dynamic") {
					switch (control.kind) {
						case Return:
							if (!OcamlControlPlan.isAdmittedDynamicReturnPayload(payload))
								throw 'Control decision "${control.id}" has an invalid Dynamic return carrier.';
							requireRepresentation(representationById, payload.inputRepresentationId, payload.inputSemanticTypeId, payload.inputCarrierTypeId,
								OcamlRepresentationDomain.InternalValue, 'Control decision "${control.id}" input');
							requireRepresentation(representationById, payload.outputRepresentationId, payload.outputSemanticTypeId,
								payload.outputCarrierTypeId, OcamlRepresentationDomain.InternalValue, 'Control decision "${control.id}" output');
						case Throw:
							if (!OcamlControlPlan.isAdmittedDynamicThrowPayload(payload))
								throw 'Control decision "${control.id}" has an invalid Dynamic exception carrier.';
						case _:
							throw 'Control decision "${control.id}" has a Dynamic payload on unsupported transfer ${control.kind}.';
					}
				} else if (!OcamlControlPlan.isAdmittedHaxeExceptionThrowPayload(payload)
					&& !OcamlControlPlan.isAdmittedEnumThrowPayload(payload)) {
					requireRepresentation(representationById, payload.inputRepresentationId, payload.inputSemanticTypeId, payload.inputCarrierTypeId,
						OcamlRepresentationDomain.InternalValue, 'Control decision "${control.id}" input');
					requireRepresentation(representationById, payload.outputRepresentationId, payload.outputSemanticTypeId, payload.outputCarrierTypeId,
						OcamlRepresentationDomain.InternalValue, 'Control decision "${control.id}" output');
				}
				final nominal = payload.nominalRepresentation;
				if (nominal != null) {
					final representation = representationById.get(payload.inputRepresentationId);
					if (representation == null
						|| representation.nominalTargetModuleName != nominal.targetModuleName
						|| representation.nominalTargetTypeName != nominal.targetTypeName
						|| representation.nominalLayoutRevision != nominal.layoutRevision
						|| representation.proof.id != nominal.representationProofId) {
						throw 'Control decision "${control.id}" does not match its sealed nominal representation proof.';
					}
				}
			}
			if (control.targetKind == OcamlControlTargetKind.Loop) {
				final target = controlTargetById.get(control.targetId);
				if (target == null)
					throw 'Control decision "${control.id}" refers to missing loop target "${control.targetId}".';
				if (target.functionId != control.functionId
					|| target.programRevision != control.programRevision
					|| target.bodyRevision != control.bodyRevision
					|| target.pipelineRevision != control.pipelineRevision) {
					throw 'Control decision "${control.id}" and loop target "${target.id}" disagree about their owning function or revision.';
				}
			}
		}
		final sortedCatchChains = controlCatchChains.copy();
		sortedCatchChains.sort((left, right) -> Reflect.compare(left.id, right.id));
		final catchChainIds:Map<String, Bool> = [];
		for (chain in sortedCatchChains) {
			OcamlControlPlan.requireCatchChain(chain);
			if (catchChainIds.exists(chain.id))
				throw 'Control catch-chain identity "${chain.id}" occurs more than once.';
			if (!controlAdmissionByFunction.exists(chain.functionId))
				throw 'Control catch chain "${chain.id}" has no complete function-admission snapshot.';
			for (clause in chain.clauses) {
				if (clause.semanticTypeId != "Dynamic" && !OcamlControlPlan.isAdmittedHaxeExceptionCatchClause(clause)) {
					requireRepresentation(representationById, clause.outputRepresentationId, clause.semanticTypeId, clause.outputCarrierTypeId,
						OcamlRepresentationDomain.InternalValue, 'Control catch clause "${clause.id}" output');
				}
				final nominal = clause.nominalRepresentation;
				if (nominal != null) {
					final representation = representationById.get(clause.outputRepresentationId);
					if (representation == null
						|| representation.nominalTargetModuleName != nominal.targetModuleName
						|| representation.nominalTargetTypeName != nominal.targetTypeName
						|| representation.nominalLayoutRevision != nominal.layoutRevision
						|| representation.proof.id != nominal.representationProofId) {
						throw 'Control catch clause "${clause.id}" does not match its sealed nominal representation proof.';
					}
				}
			}
			catchChainIds.set(chain.id, true);
		}
		for (admission in sortedControlAdmissions) {
			final controlsForFunction = sortedControls.filter(control -> control.functionId == admission.functionId);
			final catchesForFunction = sortedCatchChains.filter(chain -> chain.functionId == admission.functionId);
			final returnFamily = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Return);
			final loopFamily = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Loop);
			final throwFamily = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Throw);
			if (returnFamily.decisionCount != Lambda.count(controlsForFunction, control -> control.kind == OcamlControlTransferKind.Return)
				|| loopFamily.decisionCount != Lambda.count(controlsForFunction,
					control -> control.kind == OcamlControlTransferKind.Break || control.kind == OcamlControlTransferKind.Continue)
				|| throwFamily.decisionCount != Lambda.count(controlsForFunction, control -> control.kind == OcamlControlTransferKind.Throw)
				|| Lambda.count(admission.catches, entry -> entry.status == OcamlControlAdmissionStatus.Admitted) != catchesForFunction.length) {
				throw 'Control admission "${admission.id}" disagrees with the report decisions or catch chains for function "${admission.functionId}".';
			}
		}
		final sortedLocalConversions = localConversions.copy();
		sortedLocalConversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		final sortedContainerElementConversions = containerElementConversions.copy();
		sortedContainerElementConversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		final sortedContainerElementRequiredConversionIds = containerElementRequiredConversionIds.copy();
		sortedContainerElementRequiredConversionIds.sort(Reflect.compare);
		final requiredContainerElementConversionById:Map<String, Bool> = [];
		for (id in sortedContainerElementRequiredConversionIds) {
			if (id.length == 0)
				throw "Container-element required conversion inventory contains an empty identity.";
			if (requiredContainerElementConversionById.exists(id))
				throw 'Container-element required conversion identity "$id" occurs more than once.';
			requiredContainerElementConversionById.set(id, true);
		}
		final containerElementConversionById:Map<String, Bool> = [];
		for (conversion in sortedContainerElementConversions) {
			if (containerElementConversionById.exists(conversion.id))
				throw 'Container-element conversion identity "${conversion.id}" occurs more than once.';
			if (!requiredContainerElementConversionById.exists(conversion.id))
				throw 'Container-element conversion "${conversion.id}" is absent from the required occurrence inventory.';
			containerElementConversionById.set(conversion.id, true);
		}
		for (id in sortedContainerElementRequiredConversionIds) {
			if (!containerElementConversionById.exists(id))
				throw 'Required container-element occurrence "$id" has no sealed conversion.';
		}
		final requirementById:Map<String, OcamlRuntimeRequirement> = [];
		for (requirement in requirements) {
			if (requirementById.exists(requirement.id))
				throw 'Lowered runtime requirement identity "${requirement.id}" occurs more than once.';
			requirementById.set(requirement.id, requirement);
		}
		final includedRequirementIds:Map<String, Bool> = [];
		for (representation in sortedRepresentations) {
			for (expected in OcamlRuntimeRequirementLedger.requirementsForRepresentationDecision(representation)) {
				final recorded = requirementById.get(expected.id);
				if (recorded == null)
					throw 'Program representation "${representation.id}" refers to missing runtime requirement "${expected.id}".';
				if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expected))
					throw 'Program representation "${representation.id}" disagrees with runtime requirement "${expected.id}".';
				includedRequirementIds.set(expected.id, true);
			}
		}
		for (entry in sorted) {
			for (requirementId in entry.runtimeRequirementIds) {
				if (!requirementById.exists(requirementId))
					throw 'Lowered place plan "${entry.id}" refers to missing runtime requirement "$requirementId".';
				includedRequirementIds.set(requirementId, true);
			}
		}
		for (operation in sortedAnonymousOperations) {
			for (expected in OcamlAnonymousStructureRuntimeRequirementRecorder.requirements(operation)) {
				final recorded = requirementById.get(expected.id);
				if (recorded == null)
					throw 'Anonymous operation "${operation.id}" refers to missing runtime requirement "${expected.id}".';
				if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expected))
					throw 'Anonymous operation "${operation.id}" disagrees with runtime requirement "${expected.id}".';
				includedRequirementIds.set(expected.id, true);
			}
		}
		for (decision in sortedStructuralFields) {
			for (expected in OcamlStructuralFieldRuntimeRequirementRecorder.requirements(decision)) {
				final recorded = requirementById.get(expected.id);
				if (recorded == null)
					throw 'Structural field decision "${decision.id}" refers to missing runtime requirement "${expected.id}".';
				if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expected))
					throw 'Structural field decision "${decision.id}" disagrees with runtime requirement "${expected.id}".';
				includedRequirementIds.set(expected.id, true);
			}
		}
		for (conversion in sortedLocalConversions) {
			if (conversion.conversion != OcamlLocalCarrierConversion.BoxExactEnumToDynamic)
				continue;
			final expected = OcamlEnumRuntimeRequirementRecorder.requirement(conversion);
			final recorded = requirementById.get(expected.id);
			if (recorded == null)
				throw 'Enum-to-Dynamic conversion "${conversion.id}" refers to missing runtime requirement "${expected.id}".';
			if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expected))
				throw 'Enum-to-Dynamic conversion "${conversion.id}" disagrees with runtime requirement "${expected.id}".';
			includedRequirementIds.set(expected.id, true);
		}
		for (conversion in sortedContainerElementConversions) {
			final expected = OcamlEnumRuntimeRequirementRecorder.containerElementRequirement(conversion);
			final recorded = requirementById.get(expected.id);
			if (recorded == null)
				throw 'Enum container-element conversion "${conversion.id}" refers to missing runtime requirement "${expected.id}".';
			if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expected))
				throw 'Enum container-element conversion "${conversion.id}" disagrees with runtime requirement "${expected.id}".';
			includedRequirementIds.set(expected.id, true);
		}
		for (control in sortedControls) {
			final payload = control.payload;
			if (payload == null || !OcamlControlPlan.isAdmittedEnumThrowPayload(payload))
				continue;
			final expected = OcamlEnumRuntimeRequirementRecorder.throwRequirement(control);
			final recorded = requirementById.get(expected.id);
			if (recorded == null)
				throw 'Direct enum throw "${control.id}" refers to missing runtime requirement "${expected.id}".';
			if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expected))
				throw 'Direct enum throw "${control.id}" disagrees with runtime requirement "${expected.id}".';
			includedRequirementIds.set(expected.id, true);
		}
		for (conversion in sortedIMapInterfaceConversions) {
			final expectedRequirements = OcamlRuntimeRequirementLedger.requirementsForIMapInterfaceConversion(conversion);
			for (expected in expectedRequirements) {
				final recorded = requirementById.get(expected.id);
				if (recorded == null)
					throw 'IMap interface conversion "${conversion.id}" refers to missing runtime requirement "${expected.id}".';
				if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expected))
					throw 'IMap interface conversion "${conversion.id}" disagrees with runtime requirement "${expected.id}".';
				includedRequirementIds.set(expected.id, true);
			}
		}
		for (call in sortedCalls) {
			if (call.standardIMapTarget != null) {
				final expectedIds = OcamlStandardIMapCallContract.runtimeRequirementIds(call.id, call.standardIMapTarget);
				final expectedRequirements = OcamlRuntimeRequirementLedger.requirementsForStandardIMapCall(call.id, call.source, call.profileEligibility,
					call.standardIMapTarget);
				if (expectedIds.length != expectedRequirements.length)
					throw 'Standard IMap call "${call.id}" has inconsistent runtime requirement identities.';
				for (index in 0...expectedIds.length) {
					final requirementId = expectedIds[index];
					final recorded = requirementById.get(requirementId);
					if (recorded == null)
						throw 'Standard IMap call "${call.id}" refers to missing runtime requirement "$requirementId".';
					if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expectedRequirements[index]))
						throw 'Standard IMap call "${call.id}" disagrees with runtime requirement "$requirementId".';
					includedRequirementIds.set(requirementId, true);
				}
			}
			if (call.structuralIteratorTarget != null) {
				final expectedIds = OcamlStructuralIteratorCallContract.runtimeRequirementIds(call.id, call.structuralIteratorTarget);
				final expectedRequirements = OcamlRuntimeRequirementLedger.requirementsForStructuralIteratorCall(call.id, call.source,
					call.profileEligibility, call.structuralIteratorTarget);
				if (expectedIds.length != expectedRequirements.length)
					throw 'Structural Iterator call "${call.id}" has inconsistent runtime requirement identities.';
				for (index in 0...expectedIds.length) {
					final requirementId = expectedIds[index];
					final recorded = requirementById.get(requirementId);
					if (recorded == null)
						throw 'Structural Iterator call "${call.id}" refers to missing runtime requirement "$requirementId".';
					if (haxe.Json.stringify(recorded) != haxe.Json.stringify(expectedRequirements[index]))
						throw 'Structural Iterator call "${call.id}" disagrees with runtime requirement "$requirementId".';
					includedRequirementIds.set(requirementId, true);
				}
			}
		}
		final includedRequirements = [
			for (requirement in requirements)
				if (includedRequirementIds.exists(requirement.id)) requirement
		];
		includedRequirements.sort((left, right) -> left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
		final canonicalPlans = haxe.Json.stringify(sorted);
		final canonicalRequirements = haxe.Json.stringify(includedRequirements);
		final canonicalRepresentations = haxe.Json.stringify(sortedRepresentations);
		final canonicalAnonymousStructures = haxe.Json.stringify({
			structures: sortedAnonymousStructures,
			operations: sortedAnonymousOperations
		});
		final canonicalStructuralFields = haxe.Json.stringify(sortedStructuralFields);
		final sortedUnsafeOperations = unsafeOperations.copy();
		sortedUnsafeOperations.sort((left, right) -> Reflect.compare(left.id, right.id));
		final unsafeByConversionId:Map<String, OcamlUnsafeOperationRecord> = [];
		for (operation in sortedUnsafeOperations) {
			if (unsafeByConversionId.exists(operation.conversionId))
				throw 'Unsafe-operation ledger contains more than one proof for conversion "${operation.conversionId}".';
			unsafeByConversionId.set(operation.conversionId, operation);
		}
		for (conversion in sortedLocalConversions) {
			final operation = unsafeByConversionId.get(conversion.id);
			if ((conversion.unsafeOperation == null) != (operation == null))
				throw 'Local conversion "${conversion.id}" and the unsafe-operation ledger disagree about proof ownership.';
			if (conversion.unsafeOperation != null && conversion.unsafeOperation.id != operation.id)
				throw 'Local conversion "${conversion.id}" names unsafe proof "${conversion.unsafeOperation.id}", but the ledger contains "${operation.id}".';
		}
		for (conversion in sortedContainerElementConversions) {
			final operation = unsafeByConversionId.get(conversion.id);
			if (operation == null || conversion.unsafeOperation.id != operation.id)
				throw 'Container-element conversion "${conversion.id}" does not own its recorded unsafe proof.';
		}
		final expectedUnsafeOperationCount = sortedLocalConversions.filter(conversion -> conversion.unsafeOperation != null).length
			+ sortedContainerElementConversions.length;
		if (sortedUnsafeOperations.length != expectedUnsafeOperationCount)
			throw "Unsafe-operation ledger contains a proof that is not owned by a sealed local or container-element conversion.";
		final canonicalLocalConversions = haxe.Json.stringify(sortedLocalConversions);
		final canonicalRepresentedArrays = haxe.Json.stringify(sortedRepresentedArrays);
		final canonicalArrayLiteralProducerRevision = OcamlArrayLiteralProducerContract.planRevision(sortedArrayLiteralProducers);
		final canonicalContainerElementRequiredConversionIds = haxe.Json.stringify(sortedContainerElementRequiredConversionIds);
		final canonicalContainerElementConversions = haxe.Json.stringify(sortedContainerElementConversions);
		final canonicalUnsafeOperations = haxe.Json.stringify(sortedUnsafeOperations);
		final canonicalIMapInterfaces = haxe.Json.stringify({
			conversions: sortedIMapInterfaceConversions,
			calls: sortedIMapInterfaceCalls
		});
		final canonicalCalls = haxe.Json.stringify({
			calls: sortedCalls,
			callableBoundaries: sortedCallableBoundaries
		});
		final canonicalFunctionResultBoundaries = haxe.Json.stringify(sortedFunctionResultBoundaries);
		final canonicalControlTargets = haxe.Json.stringify(sortedControlTargets);
		final canonicalControls = haxe.Json.stringify({
			targets: sortedControlTargets,
			decisions: sortedControls,
			catchChains: sortedCatchChains
		});
		final canonicalCatchChains = haxe.Json.stringify(sortedCatchChains);
		final canonicalControlAdmissions = haxe.Json.stringify(sortedControlAdmissions);
		final report = {
			schemaVersion: SCHEMA_VERSION,
			model: "typed-ocaml-lowered-place",
			representationModel: "typed-ocaml-program-representation",
			representationScope: REPRESENTATION_SCOPE,
			representationRevision: "sha256:" + Sha256.encode(canonicalRepresentations),
			representationCount: sortedRepresentations.length,
			representations: sortedRepresentations,
			representedArrayModel: OcamlRepresentationRegistry.ARRAY_DESCRIPTOR_MODEL_REVISION,
			representedArrayRevision: "sha256:" + Sha256.encode(canonicalRepresentedArrays),
			representedArrayCount: sortedRepresentedArrays.length,
			representedArrays: sortedRepresentedArrays,
			arrayLiteralProducerModel: OcamlArrayLiteralProducerContract.MODEL_REVISION,
			arrayLiteralProducerRevision: canonicalArrayLiteralProducerRevision,
			arrayLiteralProducerCount: sortedArrayLiteralProducers.length,
			arrayLiteralProducers: sortedArrayLiteralProducers,
			anonymousStructureModel: OcamlAnonymousStructureContract.MODEL_REVISION,
			anonymousStructureRevision: "sha256:" + Sha256.encode(canonicalAnonymousStructures),
			anonymousStructureCount: sortedAnonymousStructures.length,
			anonymousStructures: sortedAnonymousStructures,
			anonymousStructureOperationCount: sortedAnonymousOperations.length,
			anonymousStructureOperations: sortedAnonymousOperations,
			structuralFieldModel: OcamlStructuralFieldContract.MODEL,
			structuralFieldRevision: "sha256:" + Sha256.encode(canonicalStructuralFields),
			structuralFieldCount: sortedStructuralFields.length,
			structuralFields: sortedStructuralFields,
			iMapInterfaceModel: OcamlIMapInterfacePlan.MODEL,
			iMapInterfaceRevision: "sha256:" + Sha256.encode(canonicalIMapInterfaces),
			iMapInterfaceConversionCount: sortedIMapInterfaceConversions.length,
			iMapInterfaceConversions: sortedIMapInterfaceConversions,
			iMapInterfaceCallCount: sortedIMapInterfaceCalls.length,
			iMapInterfaceCalls: sortedIMapInterfaceCalls,
			localConversionModel: "typed-ocaml-local-carrier-conversions-v3",
			localConversionRevision: "sha256:" + Sha256.encode(canonicalLocalConversions),
			localConversionCount: sortedLocalConversions.length,
			localConversions: sortedLocalConversions,
			containerElementConversionModel: "typed-ocaml-container-element-conversions-v1",
			containerElementRequiredConversionModel: "typed-ocaml-required-container-element-conversions-v1",
			containerElementRequiredConversionRevision: "sha256:" + Sha256.encode(canonicalContainerElementRequiredConversionIds),
			containerElementRequiredConversionCount: sortedContainerElementRequiredConversionIds.length,
			containerElementRequiredConversionIds: sortedContainerElementRequiredConversionIds,
			containerElementConversionRevision: "sha256:" + Sha256.encode(canonicalContainerElementConversions),
			containerElementConversionCount: sortedContainerElementConversions.length,
			containerElementConversions: sortedContainerElementConversions,
			unsafeOperationModel: "proof-backed-admitted-unsafe-operations-v1",
			unsafeOperationCompleteness: "exact-null-int-null-bool-inline-dynamic-and-enum-to-dynamic-local-and-container-slices",
			unsafeOperationRevision: "sha256:" + Sha256.encode(canonicalUnsafeOperations),
			unsafeOperationCount: sortedUnsafeOperations.length,
			unsafeOperations: sortedUnsafeOperations,
			callModel: "typed-ocaml-directional-call-boundary-v20",
			structuralIteratorConsumerModel: OcamlStructuralIteratorCallContract.MODEL,
			callRevision: "sha256:" + Sha256.encode(canonicalCalls),
			callCount: sortedCalls.length,
			calls: sortedCalls,
			callableBoundaryCount: sortedCallableBoundaries.length,
			callableBoundaries: sortedCallableBoundaries,
			functionResultBoundaryModel: OcamlFunctionResultBoundary.MODEL,
			functionResultBoundaryRevision: "sha256:" + Sha256.encode(canonicalFunctionResultBoundaries),
			functionResultBoundaryCount: sortedFunctionResultBoundaries.length,
			functionResultBoundaries: sortedFunctionResultBoundaries,
			controlModel: "typed-ocaml-function-loop-throw-and-catch-control-v20",
			controlRevision: "sha256:" + Sha256.encode(canonicalControls),
			controlCount: sortedControls.length,
			controls: sortedControls,
			controlCatchModel: "typed-ocaml-represented-value-catch-chain-v3",
			controlCatchRevision: "sha256:" + Sha256.encode(canonicalCatchChains),
			controlCatchCount: sortedCatchChains.length,
			controlCatches: sortedCatchChains,
			controlTargetModel: "typed-ocaml-lexical-loop-target-v1",
			controlTargetRevision: "sha256:" + Sha256.encode(canonicalControlTargets),
			controlTargetCount: sortedControlTargets.length,
			controlTargets: sortedControlTargets,
			controlAdmissionModel: OcamlControlAdmissionContract.MODEL,
			controlAdmissionRevision: "sha256:" + Sha256.encode(canonicalControlAdmissions),
			controlAdmissionCount: sortedControlAdmissions.length,
			controlAdmissions: sortedControlAdmissions,
			staticStorageModel: "typed-ocaml-static-storage",
			staticStorageRevision: staticStorageRevision,
			staticStorageCount: sortedStaticStorage.length,
			staticStorage: sortedStaticStorage,
			admittedInputRevision: "sha256:" + Sha256.encode(canonicalPlans),
			planCount: sorted.length,
			plans: sorted,
			runtimeRequirementRevision: "sha256:" + Sha256.encode(canonicalRequirements),
			runtimeRequirementCount: includedRequirements.length,
			runtimeRequirements: includedRequirements
		};
		sys.io.File.saveContent(Path.join([outputDirectory, FILE_NAME]), haxe.Json.stringify(report, null, "  ") + "\n");
		artifacts.record({
			path: FILE_NAME,
			kind: OcamlArtifactKind.CompilerReport,
			owner: OcamlArtifactOwner.LoweringReport,
			sourceKind: OcamlArtifactSourceKind.Generated,
			sourcePath: null,
			license: "generated-output",
			profileEligibility: ["portable", "metal"],
			stability: OcamlArtifactStability.Stable,
			includeInSourceBundle: false
		});
	}
}
#end
