package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceReportEntry;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/** Writes the deterministic inspection artifact for sealed lowered place nodes. */
class OcamlLoweringReportWriter {
	public static inline final FILE_NAME = "ocaml_lowering_report.json";

	public static function write(outputDirectory:String, entries:Array<OcamlLoweredPlaceReportEntry>, requirements:Array<OcamlRuntimeRequirement>,
			artifacts:OcamlArtifactManifestBuilder):Void {
		final sorted = entries.copy();
		sorted.sort((left, right) -> left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
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
		final report = {
			schemaVersion: 5,
			model: "typed-ocaml-lowered-place",
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
