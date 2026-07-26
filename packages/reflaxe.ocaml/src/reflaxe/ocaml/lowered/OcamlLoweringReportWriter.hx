package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReportEntry;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationRecord;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan.OcamlStaticStorageReportEntry;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/**
	Writes the deterministic report for sealed representation and lowering facts.

	The report exposes place operations, local carrier crossings, the admitted
	unsafe-operation proofs that own those crossings, static storage, and their
	runtime requirements. It never infers those facts from generated OCaml text.
**/
class OcamlLoweringReportWriter {
	public static inline final FILE_NAME = "ocaml_lowering_report.json";

	static function requireRepresentation(byId:Map<String, OcamlRepresentationDecision>, id:String, semanticTypeId:String, carrierTypeId:String,
			domain:OcamlRepresentationDomain, owner:String):Void {
		final decision = byId.get(id);
		if (decision == null)
			throw '$owner refers to missing program representation "$id".';
		if (decision.semanticTypeId != semanticTypeId || decision.carrierTypeId != carrierTypeId || decision.domain != domain) {
			throw '$owner expects $semanticTypeId -> $carrierTypeId in $domain, but representation ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain}.';
		}
	}

	static function requireCallValue(byId:Map<String, OcamlRepresentationDecision>, value:OcamlCallValuePlan, owner:String):Void {
		requireRepresentation(byId, value.representationId, value.semanticTypeId, value.carrierTypeId, OcamlRepresentationDomain.InternalValue, owner);
	}

	public static function write(outputDirectory:String, entries:Array<OcamlLoweredPlaceReportEntry>, requirements:Array<OcamlRuntimeRequirement>,
			representations:Array<OcamlRepresentationDecision>, localConversions:Array<OcamlLocalConversionDecision>,
			unsafeOperations:Array<OcamlUnsafeOperationRecord>, calls:Array<OcamlCallDecision>, callableBoundaries:Array<OcamlCallableBoundaryPlan>,
			staticStorage:Array<OcamlStaticStorageReportEntry>, staticStorageRevision:String, artifacts:OcamlArtifactManifestBuilder):Void {
		final sorted = entries.copy();
		sorted.sort((left, right) -> left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
		final sortedRepresentations = representations.copy();
		sortedRepresentations.sort((left, right) -> left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
		final representationById:Map<String, OcamlRepresentationDecision> = [];
		for (representation in sortedRepresentations) {
			if (representationById.exists(representation.id))
				throw 'Program representation identity "${representation.id}" occurs more than once.';
			representationById.set(representation.id, representation);
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
		for (boundary in sortedCallableBoundaries) {
			OcamlCallPlan.requireFirstFamilyBoundary(boundary);
			if (callableByCallee.exists(boundary.calleeId))
				throw 'Callable boundary identity "${boundary.calleeId}" occurs more than once.';
			if (boundary.arguments.length != 1)
				throw 'Callable boundary "${boundary.id}" has ${boundary.arguments.length} arguments instead of the admitted arity 1.';
			requireCallValue(representationById, boundary.arguments[0], 'Callable boundary "${boundary.id}" argument');
			requireCallValue(representationById, boundary.result, 'Callable boundary "${boundary.id}" result');
			callableByCallee.set(boundary.calleeId, boundary);
		}
		for (call in sortedCalls) {
			OcamlCallPlan.requireFirstFamilyCall(call);
			if (call.arguments.length != 1)
				throw 'Call "${call.id}" has ${call.arguments.length} arguments instead of the admitted arity 1.';
			requireCallValue(representationById, call.arguments[0], 'Call "${call.id}" argument');
			requireCallValue(representationById, call.result, 'Call "${call.id}" result');
			final boundary = callableByCallee.get(call.calleeId);
			if (boundary == null)
				throw 'Call "${call.id}" refers to missing callable boundary "${call.calleeId}".';
			if (boundary.kind != call.kind
				|| boundary.sourceModuleId != call.sourceModuleId
				|| boundary.sourceTypeName != call.sourceTypeName
				|| boundary.sourceFieldName != call.sourceFieldName
				|| !OcamlCallPlan.sameValue(boundary.arguments[0], call.arguments[0])
				|| !OcamlCallPlan.sameValue(boundary.result, call.result)) {
				throw 'Call "${call.id}" disagrees with callable boundary "${boundary.id}".';
			}
		}
		final requirementById:Map<String, OcamlRuntimeRequirement> = [];
		for (requirement in requirements) {
			if (requirementById.exists(requirement.id))
				throw 'Lowered runtime requirement identity "${requirement.id}" occurs more than once.';
			requirementById.set(requirement.id, requirement);
		}
		final includedRequirementIds:Map<String, Bool> = [];
		for (entry in sorted) {
			for (requirementId in entry.runtimeRequirementIds) {
				if (!requirementById.exists(requirementId))
					throw 'Lowered place plan "${entry.id}" refers to missing runtime requirement "$requirementId".';
				includedRequirementIds.set(requirementId, true);
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
		final sortedLocalConversions = localConversions.copy();
		sortedLocalConversions.sort((left, right) -> Reflect.compare(left.id, right.id));
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
		if (sortedUnsafeOperations.length != sortedLocalConversions.filter(conversion -> conversion.unsafeOperation != null).length)
			throw "Unsafe-operation ledger contains a proof that is not owned by a sealed local conversion.";
		final canonicalLocalConversions = haxe.Json.stringify(sortedLocalConversions);
		final canonicalUnsafeOperations = haxe.Json.stringify(sortedUnsafeOperations);
		final canonicalCalls = haxe.Json.stringify({
			calls: sortedCalls,
			callableBoundaries: sortedCallableBoundaries
		});
		final report = {
			schemaVersion: 14,
			model: "typed-ocaml-lowered-place",
			representationModel: "typed-ocaml-program-representation",
			representationScope: "exact-int-bool-nullable-field-defaults-direct-simple-assignment-array-int-locals-v9",
			representationRevision: "sha256:" + Sha256.encode(canonicalRepresentations),
			representationCount: sortedRepresentations.length,
			representations: sortedRepresentations,
			localConversionModel: "typed-ocaml-local-carrier-conversions-v1",
			localConversionRevision: "sha256:" + Sha256.encode(canonicalLocalConversions),
			localConversionCount: sortedLocalConversions.length,
			localConversions: sortedLocalConversions,
			unsafeOperationModel: "proof-backed-admitted-unsafe-operations-v1",
			unsafeOperationCompleteness: "exact-null-int-and-null-bool-local-slices-only",
			unsafeOperationRevision: "sha256:" + Sha256.encode(canonicalUnsafeOperations),
			unsafeOperationCount: sortedUnsafeOperations.length,
			unsafeOperations: sortedUnsafeOperations,
			callModel: "typed-ocaml-call-boundary-v1",
			callRevision: "sha256:" + Sha256.encode(canonicalCalls),
			callCount: sortedCalls.length,
			calls: sortedCalls,
			callableBoundaryCount: sortedCallableBoundaries.length,
			callableBoundaries: sortedCallableBoundaries,
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
