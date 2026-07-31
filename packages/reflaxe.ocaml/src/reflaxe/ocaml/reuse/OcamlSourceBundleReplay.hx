package reflaxe.ocaml.reuse;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactClaim;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactEntry;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import reflaxe.ocaml.reuse.OcamlSourceBundleCandidate.OcamlSourceBundleIndexEntry;
import reflaxe.output.OutputManager;

/** Completed exact replay and its freshly rebuilt target artifact inventory. **/
typedef OcamlSourceBundleReplayResult = {
	final artifacts:OcamlArtifactManifestBuilder;
	final fileReplayMilliseconds:Int;
	final receiptAndManifestMilliseconds:Int;
	final replayAndValidationMilliseconds:Int;
}

/** Identifies decoded cache content that cannot be trusted for publication. **/
class OcamlSourceBundleReplayCorruption extends haxe.Exception {}

/**
	Reconstructs one exact source bundle through current output ownership.

	Framework-owned files pass through `OutputManager` so the request receives a
	fresh generated-file receipt. Target-owned files are registered as current
	claims, then a new artifact manifest is sealed and validated. No public
	directory or prior generated file participates as semantic input.
**/
class OcamlSourceBundleReplay {
	/** Writes and validates a decoded candidate inside the active private transaction. **/
	public static function run(candidate:OcamlSourceBundleCandidate, output:OutputManager):OcamlSourceBundleReplayResult {
		final started = haxe.Timer.stamp();
		final outputDirectory = output.outputDir;
		if (outputDirectory == null || outputDirectory.length == 0)
			throw "reflaxe.ocaml: exact source replay requires an active output directory";

		final fileReplayStarted = haxe.Timer.stamp();
		for (entry in candidate.entries) {
			final bytes = candidate.copyFile(entry);
			if (entry.owner == "reflaxe-framework")
				output.replayFrameworkFile(entry.path, bytes);
			else
				output.replayTargetOwnedFile(entry.path, bytes);
		}
		final fileReplayMilliseconds = elapsedMilliseconds(fileReplayStarted);

		final receiptAndManifestStarted = haxe.Timer.stamp();
		output.finishFrameworkReplay();

		final artifacts = new OcamlArtifactManifestBuilder(outputDirectory, candidate.programRevision, candidate.configurationRevision, candidate.profile);
		for (entry in candidate.entries) {
			if (entry.owner != "reflaxe-framework")
				artifacts.record(toClaim(entry));
		}
		artifacts.recordFrameworkModules();
		final report = artifacts.seal(candidate.semanticRuntimeAuthority, candidate.nativeDependenciesAuthority);
		if (!report.summary.completeForSourceBundle || report.summary.sourceBundleRevision != candidate.sourceBundleRevision)
			throw new OcamlSourceBundleReplayCorruption("reflaxe.ocaml: replayed source manifest does not match the cached source revision");
		if (!entriesEqual(candidate.entries, report.entries))
			throw new OcamlSourceBundleReplayCorruption("reflaxe.ocaml: replayed source claims do not match the cached source bundle");
		OcamlArtifactManifestSchema.loadAndValidate(outputDirectory, candidate.programRevision, candidate.configurationRevision);
		return {
			artifacts: artifacts,
			fileReplayMilliseconds: fileReplayMilliseconds,
			receiptAndManifestMilliseconds: elapsedMilliseconds(receiptAndManifestStarted),
			replayAndValidationMilliseconds: elapsedMilliseconds(started)
		};
	}

	static function toClaim(entry:OcamlSourceBundleIndexEntry):OcamlArtifactClaim {
		return {
			path: entry.path,
			kind: cast entry.kind,
			owner: cast entry.owner,
			sourceKind: cast entry.sourceKind,
			sourcePath: entry.sourcePath,
			license: entry.license,
			profileEligibility: entry.profileEligibility.copy(),
			stability: cast entry.stability,
			includeInSourceBundle: entry.includeInSourceBundle
		};
	}

	static function entriesEqual(left:Array<OcamlSourceBundleIndexEntry>, right:Array<OcamlArtifactEntry>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length) {
			final a = left[index];
			final b = right[index];
			if (a.path != b.path
				|| a.bytes != b.bytes
				|| a.sha256 != b.sha256
				|| a.kind != b.kind
				|| a.owner != b.owner
				|| a.sourceKind != b.sourceKind
				|| a.sourcePath != b.sourcePath
				|| a.license != b.license
				|| a.stability != b.stability
				|| a.includeInSourceBundle != b.includeInSourceBundle
				|| !stringsEqual(a.profileEligibility, b.profileEligibility))
				return false;
		}
		return true;
	}

	static function stringsEqual(left:Array<String>, right:Array<String>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length) {
			if (left[index] != right[index])
				return false;
		}
		return true;
	}

	static function elapsedMilliseconds(started:Float):Int
		return Std.int(Math.max(0, (haxe.Timer.stamp() - started) * 1000));
}
#end
