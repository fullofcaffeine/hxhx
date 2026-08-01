import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactEntry;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import sys.FileSystem;
import sys.io.File;

/**
 * Reseals the evidence surrounding one deliberately edited lowering report.
 *
 * Corruption fixtures change one control decision so the public inspector can
 * test that decision's semantic validation. The edited report must first
 * receive matching section hashes, file digest, byte count, and artifact-set
 * revision. Otherwise the inspector also reports unrelated integrity failures,
 * and a matching semantic error would not prove that the fixture isolated the
 * boundary it claims to test. Section hashes include the catch-chain and
 * runtime-requirement inventories because some control decisions have matching
 * records there.
 *
 * The helper deliberately uses the production artifact schema to recompute and
 * validate the outer manifest. Raw `Dynamic` values are limited to parsing the
 * JSON fixture; production revision rules remain owned by typed target code.
 */
class RecomputeLoweringControlRevision {
	/**
	 * Updates the report and its sibling artifact manifest, then validates the
	 * complete output inventory before returning to the corruption fixture.
	 * `--preserve-control-revision` leaves a deliberately stale inner revision
	 * intact while still resealing the outer artifact manifest.
	 */
	static function main():Void {
		final arguments = Sys.args();
		final preserveControlRevision = arguments.length == 2 && arguments[0] == "--preserve-control-revision";
		if ((!preserveControlRevision && arguments.length != 1) || (preserveControlRevision && arguments.length != 2))
			throw "Usage: RecomputeLoweringControlRevision [--preserve-control-revision] <ocaml_lowering_report.json>";

		final reportPath = arguments[preserveControlRevision ? 1 : 0];
		if (Path.withoutDirectory(reportPath) != "ocaml_lowering_report.json")
			throw 'Expected an ocaml_lowering_report.json path, received "$reportPath".';
		final outputDirectory = Path.directory(reportPath);
		final manifestPath = Path.join([outputDirectory, OcamlArtifactManifestSchema.FILE_NAME]);
		if (!FileSystem.exists(manifestPath) || FileSystem.isDirectory(manifestPath))
			throw 'Cannot reseal lowering evidence because "$manifestPath" is missing.';

		final report:Dynamic = Json.parse(File.getContent(reportPath));
		if (!preserveControlRevision) {
			final canonicalControls = Json.stringify({
				targets: Reflect.field(report, "controlTargets"),
				decisions: Reflect.field(report, "controls"),
				catchChains: Reflect.field(report, "controlCatches")
			});
			Reflect.setField(report, "controlRevision", "sha256:" + Sha256.encode(canonicalControls));
		}
		recomputeSectionRevision(report, "controlCatchRevision", "controlCatches");
		recomputeSectionRevision(report, "controlTargetRevision", "controlTargets");
		recomputeSectionRevision(report, "runtimeRequirementRevision", "runtimeRequirements");
		File.saveContent(reportPath, Json.stringify(report, null, "  ") + "\n");

		final manifest:Dynamic = Json.parse(File.getContent(manifestPath));
		final entries:Array<Dynamic> = cast Reflect.field(manifest, "entries");
		final reportDigest = OcamlArtifactManifestSchema.digestFile(reportPath);
		var reportEntry:Null<Dynamic> = null;
		for (entry in entries) {
			if (Reflect.field(entry, "path") == "ocaml_lowering_report.json") {
				reportEntry = entry;
				break;
			}
		}
		if (reportEntry == null)
			throw 'Artifact manifest "$manifestPath" has no lowering-report entry.';
		Reflect.setField(reportEntry, "sha256", reportDigest.sha256);
		Reflect.setField(reportEntry, "bytes", reportDigest.bytes);

		final typedEntries:Array<OcamlArtifactEntry> = cast entries;
		final authorities:Dynamic = Reflect.field(manifest, "authorities");
		final semanticRuntime = Reflect.field(authorities, "semanticRuntime");
		final nativeDependencies = Reflect.field(authorities, "nativeDependencies");
		final programRevision:String = Reflect.field(manifest, "programRevision");
		final configurationRevision:String = Reflect.field(manifest, "configurationRevision");
		final profile:String = Reflect.field(manifest, "profile");
		final summary:Dynamic = Reflect.field(manifest, "summary");
		final sourceEntries = typedEntries.filter(entry -> entry.includeInSourceBundle);
		Reflect.setField(summary, "sourceBundleRevision",
			OcamlArtifactManifestSchema.calculateArtifactRevision(programRevision, configurationRevision, profile, sourceEntries, semanticRuntime,
				nativeDependencies, "source-bundle"));
		Reflect.setField(summary, "artifactSetRevision",
			OcamlArtifactManifestSchema.calculateArtifactRevision(programRevision, configurationRevision, profile, typedEntries, semanticRuntime,
				nativeDependencies, "artifact-set"));
		File.saveContent(manifestPath, Json.stringify(manifest, null, "  ") + "\n");

		// A fixture may proceed only when every unrelated manifest invariant is
		// valid after resealing. The inspector can then report just the intended
		// semantic contradiction in the edited lowering row.
		OcamlArtifactManifestSchema.loadAndValidateCurrent(outputDirectory);
	}

	/** Recomputes one report section hash with the writer's JSON encoding. */
	static function recomputeSectionRevision(report:Dynamic, revisionField:String, inventoryField:String):Void {
		final inventory = Reflect.field(report, inventoryField);
		Reflect.setField(report, revisionField, "sha256:" + Sha256.encode(Json.stringify(inventory)));
	}
}
