package reflaxe.ocaml.reuse;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.io.Path;
import reflaxe.lifecycle.FinalProgramFingerprintSnapshot;
import reflaxe.lifecycle.TargetReuseCatalog.TargetReuseCatalogRealmObservation;
import reflaxe.lifecycle.TargetReuseCatalog.TargetReuseCatalogStats;
import reflaxe.lifecycle.TargetReuseProbe;
import reflaxe.lifecycle.TargetReuseRevisionComponent;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.reuse.OcamlSourceBundleShadowReplay.OcamlSourceBundleShadowReplayResult;
import sys.io.File;

/**
	Writes a redacted observation of the exact target-source reuse decision.

	The report is intentionally volatile and excluded from the reproducible
	source bundle. It contains only revisions, counts, stable blockers, and
	phase durations. Unimplemented observation stages use explicit status values
	and `null` measurements so readers cannot mistake missing evidence for zero
	cost or a successful proof.
**/
class OcamlTargetReuseReportWriter {
	public static inline final FILE_NAME = "ocaml_target_reuse_observation.json";
	public static inline final MODEL = "reflaxe-ocaml-target-reuse-observation";
	public static inline final SCHEMA_VERSION = 1;

	/** Writes one request-scoped report and registers its artifact ownership. **/
	public static function write(outputDirectory:String, snapshot:FinalProgramFingerprintSnapshot, probe:TargetReuseProbe,
			components:Array<TargetReuseRevisionComponent>, targetRevisionObservationMilliseconds:Int, fingerprintAndKeyMilliseconds:Int,
			missPreparationMilliseconds:Int, realm:TargetReuseCatalogRealmObservation, catalog:TargetReuseCatalogStats,
			candidate:Null<OcamlSourceBundleCandidate>, shadow:Null<OcamlSourceBundleShadowReplayResult>, rejectedPayloadBytes:Null<Int>,
			artifacts:OcamlArtifactManifestBuilder):Void {
		final sortedComponents = components.copy();
		sortedComponents.sort((left, right) -> Reflect.compare(left.name, right.name));
		final sourceAuthorityBlockers = snapshot.sourceAuthorityBlockers();
		sourceAuthorityBlockers.sort(Reflect.compare);
		final blockers = probe.blockers();
		blockers.sort(Reflect.compare);
		final sourceBundleCandidate:Dynamic = candidate == null ? {
			status: "entry-budget-exceeded",
			entryCount: null,
			packedBytes: null,
			indexBytes: null,
			payloadBytes: rejectedPayloadBytes,
			maximumPayloadBytes: catalog.maximumEntryBytes,
			sourceBundleRevision: null,
			diagnosticsEligible: false
		} : {
			status: "packed-observation",
			entryCount: candidate.entries.length,
			packedBytes: candidate.packedBytes,
			indexBytes: candidate.indexBytes,
			payloadBytes: candidate.payloadBytes,
			maximumPayloadBytes: catalog.maximumEntryBytes,
			sourceBundleRevision: reportHash(candidate.sourceBundleRevision, "source-bundle revision"),
			diagnosticsEligible: candidate.diagnosticsEligible
			};
		final shadowReplay:Dynamic = shadow == null ? {
			status: "not-run-entry-budget-exceeded",
			equal: false,
			mismatchReason: "entry-budget-exceeded",
			receiptSemanticsEqual: false,
			artifactManifestEqual: false
		} : {
			status: shadow.status,
			equal: shadow.equal,
			mismatchReason: shadow.mismatchReason,
			receiptSemanticsEqual: shadow.receiptSemanticsEqual,
			artifactManifestEqual: shadow.artifactManifestEqual
			};
		final report = {
			schemaVersion: SCHEMA_VERSION,
			model: MODEL,
			mode: "observation-only",
			finalProgram: {
				schemaRevision: FinalProgramFingerprintSnapshot.SCHEMA_REVISION,
				revision: reportHash(snapshot.id, "final-program revision"),
				programMembershipRevision: reportHash(snapshot.programMembershipRevision, "program-membership revision"),
				hostRequestRevision: reportHash(snapshot.hostRequestRevision, "host-request revision"),
				compatibilityProgramRevision: reportHash(snapshot.programRevision.id, "compatibility-program revision"),
				declarationCount: snapshot.declarations().length,
				sourceAuthorityComplete: snapshot.sourceAuthorityComplete,
				sourceAuthorityBlockers: sourceAuthorityBlockers
			},
			targetRequest: {
				namespace: OcamlTargetReuseContract.NAMESPACE,
				revision: reportOptionalHash(probe.requestRevision, "target-source request revision"),
				eligible: probe.eligible,
				blockers: blockers,
				components: [
					for (component in sortedComponents)
						{
							name: component.name,
							revision: component.revision
						}
				]
			},
			timing: {
				targetRevisionObservationMilliseconds: nonNegative(targetRevisionObservationMilliseconds, "target revision observation"),
				missPreparationMilliseconds: nonNegative(missPreparationMilliseconds, "miss preparation"),
				finalProgramFingerprintAndKeyMilliseconds: nonNegative(fingerprintAndKeyMilliseconds, "final-program fingerprint and key"),
				replayAndValidationMilliseconds: shadow == null ? null : nonNegative(shadow.replayAndValidationMilliseconds, "replay and validation")
			},
			macroRealm: {
				status: "observed",
				identityRevision: reportHash(realm.identityRevision, "macro-realm identity"),
				requestSequence: realm.requestSequence,
				survivedPriorRequest: realm.survivedPriorRequest,
				resetGeneration: realm.resetGeneration,
				resetCause: realm.lastResetCause
			},
			catalog: {
				status: "observation-only",
				totalBudgetBytes: catalog.totalBudgetBytes,
				maximumEntryBytes: catalog.maximumEntryBytes,
				entryCount: catalog.entryCount,
				payloadBytes: catalog.payloadBytes,
				estimatedOverheadBytes: catalog.estimatedOverheadBytes,
				activeLeases: catalog.activeLeases,
				hits: catalog.hits,
				misses: catalog.misses,
				ineligibleRequests: catalog.ineligibleRequests,
				admissions: catalog.admissions,
				rejectedAdmissions: catalog.rejectedAdmissions,
				evictions: catalog.evictions,
				quarantines: catalog.quarantines
			},
			sourceBundleCandidate: sourceBundleCandidate,
			shadowReplay: shadowReplay,
			memory: {
				status: candidate == null ? "entry-budget-rejected-before-packing" : "exact-payload-accounting",
				candidatePayloadBytes: candidate == null ? 0 : candidate.payloadBytes,
				candidateIndexBytes: candidate == null ? 0 : candidate.indexBytes,
				rejectedPayloadBytes: rejectedPayloadBytes,
				catalogPayloadBytes: catalog.payloadBytes,
				catalogEstimatedOverheadBytes: catalog.estimatedOverheadBytes,
				evaluatorRssBytes: null,
				gcHeapBytes: null
			}
		};
		File.saveContent(Path.join([outputDirectory, FILE_NAME]), Json.stringify(report, null, "  ") + "\n");
		artifacts.record({
			path: FILE_NAME,
			kind: OcamlArtifactKind.CompilerReport,
			owner: OcamlArtifactOwner.TargetReuseReport,
			sourceKind: OcamlArtifactSourceKind.Generated,
			sourcePath: null,
			license: "generated-output",
			profileEligibility: ["portable", "metal"],
			stability: OcamlArtifactStability.Volatile,
			includeInSourceBundle: false
		});
	}

	static function nonNegative(value:Int, label:String):Int {
		if (value < 0)
			throw 'OCaml target reuse $label duration must not be negative.';
		return value;
	}

	static function reportOptionalHash(value:Null<String>, label:String):Null<String> {
		return value == null ? null : reportHash(value, label);
	}

	static function reportHash(value:String, label:String):String {
		if (StringTools.startsWith(value, "sha256:"))
			return value;
		if (!~/^[0-9a-f]{64}$/.match(value))
			throw 'OCaml target reuse $label is not a SHA-256 value.';
		return "sha256:" + value;
	}
}
#end
