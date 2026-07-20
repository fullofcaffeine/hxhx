package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReportEntry;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/** Writes the deterministic inspection artifact for sealed lowered place nodes. */
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

	public static function write(outputDirectory:String, entries:Array<OcamlLoweredPlaceReportEntry>, requirements:Array<OcamlRuntimeRequirement>,
			representations:Array<OcamlRepresentationDecision>, artifacts:OcamlArtifactManifestBuilder):Void {
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
		final report = {
			schemaVersion: 7,
			model: "typed-ocaml-lowered-place",
			representationModel: "typed-ocaml-program-representation",
			representationScope: "exact-non-null-int-v1",
			representationRevision: "sha256:" + Sha256.encode(canonicalRepresentations),
			representationCount: sortedRepresentations.length,
			representations: sortedRepresentations,
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
