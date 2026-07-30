package reflaxe.ocaml.reuse;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.io.Path;
import reflaxe.lifecycle.FinalProgramFingerprintSnapshot;
import reflaxe.lifecycle.TargetReuseProbe;
import reflaxe.lifecycle.TargetReuseRevisionComponent;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
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
			components:Array<TargetReuseRevisionComponent>, targetRevisionObservationMilliseconds:Int, missPreparationMilliseconds:Int,
			artifacts:OcamlArtifactManifestBuilder):Void {
		final sortedComponents = components.copy();
		sortedComponents.sort((left, right) -> Reflect.compare(left.name, right.name));
		final sourceAuthorityBlockers = snapshot.sourceAuthorityBlockers();
		sourceAuthorityBlockers.sort(Reflect.compare);
		final blockers = probe.blockers();
		blockers.sort(Reflect.compare);
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
				finalProgramFingerprintAndKeyMilliseconds: null,
				replayAndValidationMilliseconds: null
			},
			macroRealm: {
				status: "not-proven",
				identityRevision: null,
				resetCause: null
			},
			catalog: {
				status: "not-implemented",
				entryCount: null,
				payloadBytes: null,
				estimatedOverheadBytes: null,
				hits: null,
				misses: null
			},
			sourceBundleCandidate: {
				status: "not-observed",
				entryCount: null,
				packedBytes: null,
				indexBytes: null,
				sourceBundleRevision: null
			},
			shadowReplay: {
				status: "not-implemented",
				equal: null,
				mismatchReason: null
			},
			memory: {
				status: "not-observed",
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
