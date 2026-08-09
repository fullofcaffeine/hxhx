import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;
import reflaxe.ocaml.runtimegen.RuntimeSelectionShadowReportWriter;
import reflaxe.ocaml.runtimegen.RuntimeSelectionShadowReportWriter.RuntimeSelectionShadowReport;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;

/** Proves that requirements-only runtime selection is compared without controlling output. **/
class RuntimeSelectionShadowFixture {
	static inline final HASH_A = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
	static inline final HASH_B = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
	static inline final HASH_C = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertArrayEquals(expected:Array<String>, actual:Array<String>, label:String):Void {
		if (expected.length != actual.length)
			throw '$label length mismatch: expected ${expected.length}, found ${actual.length}';
		for (index in 0...expected.length)
			if (expected[index] != actual[index])
				throw '$label mismatch at $index: expected ${expected[index]}, found ${actual[index]}';
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failure:Null<String> = null;
		try {
			action();
		} catch (error:Dynamic) {
			failure = Std.string(error);
		}
		if (failure == null)
			throw '$label should fail.';
		if (failure.indexOf(expectedMessage) < 0)
			throw '$label failed with an unexpected message: $failure';
	}

	static function manifest():RuntimeSourceManifestSnapshot {
		return {
			schemaVersion: RuntimeSourceManifest.SCHEMA_VERSION,
			model: RuntimeSourceManifest.MODEL,
			runtimeVersion: "fixture-v1",
			revision: HASH_A,
			modules: [
				{
					module: "HxArray",
					scope: RuntimeSourceManifest.APPLICATION_SCOPE,
					files: [{path: "HxArray.ml", sha256: HASH_A, bytes: 101}],
					dependencies: ["HxRuntime"],
					duneLibraries: [],
					profiles: ["metal", "portable"],
					license: "MIT"
				},
				{
					module: "HxExtra",
					scope: RuntimeSourceManifest.APPLICATION_SCOPE,
					files: [{path: "HxExtra.ml", sha256: HASH_B, bytes: 202}],
					dependencies: ["HxRuntime"],
					duneLibraries: [],
					profiles: ["portable"],
					license: "MIT"
				},
				{
					module: "HxRuntime",
					scope: RuntimeSourceManifest.APPLICATION_SCOPE,
					files: [{path: "HxRuntime.ml", sha256: HASH_C, bytes: 303}],
					dependencies: [],
					duneLibraries: [],
					profiles: ["metal", "portable"],
					license: "MIT"
				}
			]
		};
	}

	static function requirement(id:String, root:String):OcamlRuntimeRequirement {
		return {
			id: id,
			sourceKind: OcamlRuntimeRequirementSourceKind.CompilerInfrastructure,
			sourceId: "compiler-policy:fixture",
			source: {file: "compiler-policy/fixture", min: 0, max: 0},
			semanticCapability: id,
			cause: OcamlRuntimeRequirementCause.CompilerInfrastructure,
			decisionId: "fixture:" + id,
			subject: {kind: OcamlRuntimeRequirementSubjectKind.CompilerPolicy, id: "fixture"},
			implementationFeature: id + "-v1",
			rootModules: [root],
			profileEligibility: ["metal", "portable"],
			explanation: "Focused requirements-only runtime-selection fixture."
		};
	}

	static function reasonsFor(report:RuntimeSelectionShadowReport, moduleName:String):Array<String> {
		for (entry in report.requirementsOnlySelection.inclusionReasons)
			if (entry.module == moduleName)
				return entry.reasons;
		return [];
	}

	static function main():Void {
		final sourceManifest = manifest();
		final requirements = [
			requirement("requirement:array", "HxArray"),
			requirement("requirement:core", "HxRuntime")
		];
		final currentRoots = ["HxRuntime", "HxExtra", "HxArray"];
		final currentEntries = RuntimeSourceManifest.resolveClosure(sourceManifest, currentRoots, "portable", false);
		final currentReasons = [
			{module: "HxRuntime", reasons: ["transitive:HxExtra", "core_runtime"]},
			{module: "HxExtra", reasons: ["compiler_observed"]},
			{module: "HxArray", reasons: ["recorded_requirement", "compiler_observed"]}
		];
		final report = RuntimeSelectionShadowReportWriter.build("portable", "selective", "requirements_plus_compiler_observed", HASH_B, false, sourceManifest,
			requirements, currentRoots, currentEntries, currentReasons);
		assertTrue(report.authorityStatus == "observation-only", "the shadow must not claim selection authority");
		assertTrue(report.requirementRevision == HASH_B, "the shadow must bind the sealed requirement ledger revision");
		assertTrue(report.sourceSelectionStatus == "mismatch", "an observed-only module must make the copied source sets differ");
		assertTrue(report.exactComparisonStatus == "mismatch", "roots and reasons also differ in the mismatch fixture");
		assertArrayEquals(["HxArray", "HxExtra", "HxRuntime"], report.currentSelection.roots, "normalized current roots");
		assertArrayEquals(["HxArray", "HxRuntime"], report.requirementsOnlySelection.roots, "requirements-only roots");
		assertArrayEquals(["HxExtra"], report.differences.currentOnlyRoots, "current-only roots");
		assertArrayEquals(["HxExtra"], report.differences.currentOnlyClosureModules, "current-only closure");
		assertArrayEquals(["HxExtra.ml"], [for (file in report.differences.currentOnlySourceFiles) file.path], "current-only sources");
		assertTrue(report.differences.requirementsOnlySourceFiles.length == 0, "the shadow should not invent a source file");
		assertArrayEquals(["requirement:requirement:array"], reasonsFor(report, "HxArray"), "exact requirement reason");
		assertArrayEquals(["requirement:requirement:core", "transitive:HxArray"], reasonsFor(report, "HxRuntime"), "root and transitive reasons");

		final reversedRequirements = requirements.copy();
		reversedRequirements.reverse();
		final reversedCurrentRoots = currentRoots.copy();
		reversedCurrentRoots.reverse();
		final reversedCurrentEntries = currentEntries.copy();
		reversedCurrentEntries.reverse();
		final reversedCurrentReasons = currentReasons.copy();
		reversedCurrentReasons.reverse();
		final repeated = RuntimeSelectionShadowReportWriter.build("portable", "selective", "requirements_plus_compiler_observed", HASH_B, false,
			sourceManifest, reversedRequirements, reversedCurrentRoots, reversedCurrentEntries, reversedCurrentReasons);
		assertTrue(report.reportRevision == repeated.reportRevision, "input order must not change the deterministic shadow report");
		final changedRequirementRevision = RuntimeSelectionShadowReportWriter.build("portable", "selective", "requirements_plus_compiler_observed", HASH_C,
			false, sourceManifest, requirements, currentRoots, currentEntries, currentReasons);
		assertTrue(report.reportRevision != changedRequirementRevision.reportRevision,
			"the sealed requirement revision must participate in shadow-report identity");

		final exactRoots = ["HxArray", "HxRuntime"];
		final exactEntries = RuntimeSourceManifest.resolveClosure(sourceManifest, exactRoots, "portable", false);
		final exactReasons = [
			{module: "HxArray", reasons: ["requirement:requirement:array"]},
			{module: "HxRuntime", reasons: ["requirement:requirement:core", "transitive:HxArray"]}
		];
		final exact = RuntimeSelectionShadowReportWriter.build("portable", "selective", "requirements", HASH_B, false, sourceManifest, requirements,
			exactRoots, exactEntries, exactReasons);
		assertTrue(exact.sourceSelectionStatus == "match", "equal closures, source paths, sizes, and hashes must match");
		assertTrue(exact.exactComparisonStatus == "match", "equal roots and reasons must produce an exact match");

		expectFailure("unknown current root", "Unknown OCaml runtime module",
			() -> RuntimeSelectionShadowReportWriter.build("portable", "selective", "compiler_observed", HASH_B, false, sourceManifest, requirements,
				["HxMissing"], [], []));
		expectFailure("profile-illegal requirement", "not allowed in the \"metal\" profile",
			() -> RuntimeSelectionShadowReportWriter.build("metal", "selective", "requirements", HASH_B, false, sourceManifest,
				[requirement("requirement:extra", "HxExtra")], ["HxRuntime"],
				RuntimeSourceManifest.resolveClosure(sourceManifest, ["HxRuntime"], "metal", false), []));
		expectFailure("invalid requirement revision", "invalid requirement revision",
			() -> RuntimeSelectionShadowReportWriter.build("portable", "selective", "requirements", "not-a-revision", false, sourceManifest, requirements,
				exactRoots, exactEntries, exactReasons));
		Sys.println("REFLAXE_OCAML_RUNTIME_SELECTION_SHADOW_FIXTURE:PASS");
	}
}
