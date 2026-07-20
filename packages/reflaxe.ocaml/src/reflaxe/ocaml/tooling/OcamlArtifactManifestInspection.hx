package reflaxe.ocaml.tooling;

import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import reflaxe.ocaml.tooling.InspectionReport.InspectionArtifactCount;
import reflaxe.ocaml.tooling.InspectionReport.InspectionArtifactManifest;
import sys.FileSystem;

/**
	Turns the compiler's complete generated-file inventory into a concise user view.

	The artifact schema remains the authority: this module asks that schema to
	verify every digest and every non-cache file before reporting counts. It does
	not guess ownership from filenames or treat an incomplete runtime/dependency
	inventory as packaging readiness.
**/
class OcamlArtifactManifestInspection {
	/** Validates the current output and returns a display-safe summary. **/
	public static function inspect(outputDirectory:String):InspectionArtifactManifest {
		final path = Path.join([outputDirectory, OcamlArtifactManifestSchema.FILE_NAME]);
		if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
			return failure("missing", path, "Generated-artifact manifest is missing. Run a successful reflaxe.ocaml build first.");
		try {
			final report = OcamlArtifactManifestSchema.loadAndValidateCurrent(outputDirectory);
			final ownerCounts = countBy([for (entry in report.entries) entry.owner]);
			final kindCounts = countBy([for (entry in report.entries) entry.kind]);
			final complete = report.summary.completeForSourceBundle;
			return {
				status: "present",
				path: path,
				schemaVersion: report.schemaVersion,
				model: report.model,
				programRevision: report.programRevision,
				configurationRevision: report.configurationRevision,
				profile: report.profile,
				entryCount: report.summary.entryCount,
				sourceBundleEntryCount: report.summary.sourceBundleEntryCount,
				volatileEvidenceEntryCount: report.summary.volatileEvidenceEntryCount,
				sourceBundleRevision: report.summary.sourceBundleRevision,
				artifactSetRevision: report.summary.artifactSetRevision,
				completeForSourceBundle: complete,
				semanticRuntime: report.authorities.semanticRuntime,
				nativeDependencies: report.authorities.nativeDependencies,
				ownerCounts: ownerCounts,
				kindCounts: kindCounts,
				blockers: report.summary.blockers.copy(),
				message: complete ? 'Verified ownership and digests for ${report.summary.entryCount} generated artifacts; the source bundle has all prerequisite inventories.' : 'Verified ownership and digests for ${report.summary.entryCount} generated artifacts; source-bundle packaging still has ${report.summary.blockers.length} prerequisite blocker${report.summary.blockers.length == 1 ? "" : "s"}.'
			};
		} catch (error:Dynamic) {
			return failure("invalid", path, Std.string(error));
		}
	}

	/** Renders the manifest result without presenting incomplete packaging as ready. **/
	public static function renderHuman(value:InspectionArtifactManifest):String {
		if (value.status != "present")
			return '[FAIL] Generated artifact ownership: ${value.message}';
		if (value.completeForSourceBundle == true)
			return '[PASS] Generated artifact ownership: ${value.entryCount} files verified; source bundle is complete.';
		return '[PASS] Generated artifact ownership: ${value.entryCount} files verified. [BLOCKED] Source-bundle packaging: ${value.blockers.join(" ")}';
	}

	static function countBy(values:Array<String>):Array<InspectionArtifactCount> {
		final counts:Map<String, Int> = [];
		for (value in values) {
			final current = counts.get(value);
			counts.set(value, current == null ? 1 : current + 1);
		}
		final ids = [for (id in counts.keys()) id];
		ids.sort(compareStrings);
		final result = new Array<InspectionArtifactCount>();
		for (id in ids) {
			final count = counts.get(id);
			if (count == null)
				throw 'Artifact count for "$id" disappeared during inspection.';
			final resolved:Int = cast count;
			result.push({id: id, count: resolved});
		}
		return result;
	}

	static function failure(status:String, path:String, message:String):InspectionArtifactManifest {
		return {
			status: status,
			path: path,
			schemaVersion: null,
			model: null,
			programRevision: null,
			configurationRevision: null,
			profile: null,
			entryCount: 0,
			sourceBundleEntryCount: 0,
			volatileEvidenceEntryCount: 0,
			sourceBundleRevision: null,
			artifactSetRevision: null,
			completeForSourceBundle: null,
			semanticRuntime: null,
			nativeDependencies: null,
			ownerCounts: [],
			kindCounts: [],
			blockers: [],
			message: message
		};
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
