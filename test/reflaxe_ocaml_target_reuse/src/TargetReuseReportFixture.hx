import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/** Validates the redacted report and its volatile artifact ownership. **/
class TargetReuseReportFixture {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final args = Sys.args();
		assertTrue(args.length == 1, "expected one generated OCaml output directory");
		final outputDirectory = args[0];
		final reportPath = Path.join([outputDirectory, "ocaml_target_reuse_observation.json"]);
		final manifestPath = Path.join([outputDirectory, "ocaml_artifact_manifest.json"]);
		assertTrue(FileSystem.exists(reportPath), "target reuse observation report should exist");
		assertTrue(FileSystem.exists(manifestPath), "artifact manifest should exist");

		final report:Dynamic = Json.parse(File.getContent(reportPath));
		assertTrue(report.schemaVersion == 1
			&& report.model == "reflaxe-ocaml-target-reuse-observation", "report should use the supported schema");
		assertTrue(report.mode == "observation-only", "report must not claim a production cache hit");
		assertTrue(Std.string(report.finalProgram.revision).startsWith("sha256:"), "final-program revision should be redacted");
		assertTrue(Std.string(report.targetRequest.revision).startsWith("sha256:"), "target request revision should be redacted");
		assertTrue(report.targetRequest.eligible == false, "incomplete target authority must remain ineligible");
		final blockers:Array<String> = cast report.targetRequest.blockers;
		assertTrue(blockers.contains("reflaxe.ocaml:target-reuse-disabled")
			&& blockers.contains("reflaxe.ocaml:observation-report-enabled"),
			"report should explain why observation mode cannot replay source");
		final components:Array<Dynamic> = cast report.targetRequest.components;
		assertTrue(components.length == 5
			&& components[0].name == "artifact-output-schema"
			&& components[1].name == "native-source-input"
			&& components[2].name == "runtime-input"
			&& components[4].name == "target-implementation",
			"target revision components should be complete and sorted");
		assertTrue(report.timing.targetRevisionObservationMilliseconds >= 0
			&& report.timing.finalProgramFingerprintAndKeyMilliseconds >= 0
			&& report.timing.missPreparationMilliseconds >= 0,
			"completed target phases should report non-negative durations");
		assertTrue(report.macroRealm.status == "observed"
			&& Std.string(report.macroRealm.identityRevision).startsWith("sha256:")
			&& report.macroRealm.requestSequence >= 1,
			"report should identify the current macro realm without exposing process details");
		assertTrue(report.catalog.status == "observation-only"
			&& report.catalog.totalBudgetBytes == 128 * 1024 * 1024
			&& report.catalog.maximumEntryBytes == 64 * 1024 * 1024
			&& report.catalog.entryCount == 0
			&& report.catalog.ineligibleRequests >= 1,
			"catalog report should expose bounded real counters without admitting a payload");
		assertTrue(report.sourceBundleCandidate.status == "packed-observation"
			&& report.sourceBundleCandidate.entryCount > 0
			&& report.sourceBundleCandidate.packedBytes > 0
			&& report.sourceBundleCandidate.indexBytes > 0
			&& report.sourceBundleCandidate.payloadBytes > report.sourceBundleCandidate.packedBytes
			&& Std.string(report.sourceBundleCandidate.sourceBundleRevision).startsWith("sha256:")
			&& report.sourceBundleCandidate.diagnosticsEligible == false,
			"report should describe the detached packed candidate without claiming production eligibility");
		assertTrue(report.shadowReplay.status == "stable-source-equal"
			&& report.shadowReplay.equal == true
			&& report.shadowReplay.mismatchReason == null
			&& report.shadowReplay.receiptSemanticsEqual == true
			&& report.shadowReplay.artifactManifestEqual == true
			&& report.timing.replayAndValidationMilliseconds >= 0,
			"report should prove private stable-source, receipt, and manifest equality");
		assertTrue(report.memory.status == "exact-payload-accounting"
			&& report.memory.candidatePayloadBytes == report.sourceBundleCandidate.payloadBytes
			&& report.memory.candidateIndexBytes == report.sourceBundleCandidate.indexBytes
			&& report.memory.catalogPayloadBytes == 0
			&& report.memory.catalogEstimatedOverheadBytes == 0
			&& report.memory.evaluatorRssBytes == null
			&& report.memory.gcHeapBytes == null,
			"report should expose exact owned bytes while leaving unavailable process metrics explicitly null");

		final serialized = File.getContent(reportPath);
		assertTrue(!serialized.contains(Path.normalize(Sys.getCwd())), "report must not leak the current machine path");

		final manifest:Dynamic = Json.parse(File.getContent(manifestPath));
		assertTrue(manifest.summary.completeForSourceBundle == true
			&& manifest.summary.sourceBundleRevision == report.sourceBundleCandidate.sourceBundleRevision,
			"final manifest should preserve the source revision proven by shadow replay");
		final entries:Array<Dynamic> = cast manifest.entries;
		final owned = entries.filter(entry -> entry.path == "ocaml_target_reuse_observation.json");
		assertTrue(owned.length == 1, "artifact manifest should own the reuse observation exactly once");
		assertTrue(owned[0].owner == "target-reuse-report-writer"
			&& owned[0].kind == "compiler-report"
			&& owned[0].stability == "volatile"
			&& owned[0].includeInSourceBundle == false,
			"reuse observation should be volatile evidence outside the source bundle");
		Sys.println("REFLAXE_OCAML_TARGET_REUSE_REPORT:PASS");
	}
}
