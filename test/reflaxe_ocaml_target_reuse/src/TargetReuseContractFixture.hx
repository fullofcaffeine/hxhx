import haxe.crypto.Sha256;
import reflaxe.ocaml.reuse.OcamlTargetReuseContract;
import reflaxe.ocaml.reuse.OcamlTargetReuseContract.OcamlTargetReuseObservation;

/** Focused executable checks for the fail-closed OCaml source-reuse contract. **/
class TargetReuseContractFixture {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function observation(?configurationRevision:String, ?progress:Bool = false, ?loweringReport:Bool = false, ?lifecycleTrace:Bool = false,
			?targetImplementationRevision:String, ?reuseEnabled:Bool = false, ?transactionalOutputEnabled:Bool = true,
			?mliEnabled:Bool = false):OcamlTargetReuseObservation {
		return {
			packageVersion: "0.33.4",
			pipelineRevision: "ocaml-function-plans-v61",
			sourceConfigurationRevision: configurationRevision ?? ("sha256:" + Sha256.encode("configuration")),
			outputSchemaRevision: "sha256:" + Sha256.encode("output-schema"),
			runtimeInputRevision: "sha256:" + Sha256.encode("runtime-input"),
			nativeSourceInputRevision: "sha256:" + Sha256.encode("native-source-input"),
			targetImplementationRevision: targetImplementationRevision,
			reuseEnabled: reuseEnabled,
			transactionalOutputEnabled: transactionalOutputEnabled,
			mliEnabled: mliEnabled,
			outputConfigured: true,
			progressOrTelemetryEnabled: progress,
			loweringReportEnabled: loweringReport,
			lifecycleTraceEnabled: lifecycleTrace
		};
	}

	static function testStableComponents():Void {
		final first = OcamlTargetReuseContract.revisionComponents(observation());
		final second = OcamlTargetReuseContract.revisionComponents(observation());
		assertTrue(first.length == 5, "the target observation should expose five revision domains");
		assertTrue(first[0].name == "artifact-output-schema" && first[4].name == "target-implementation-candidate",
			"revision domains should be sorted by stable name");
		for (index in 0...first.length)
			assertTrue(first[index].name == second[index].name && first[index].revision == second[index].revision,
				"equivalent observations should produce identical revisions");

		final changed = OcamlTargetReuseContract.revisionComponents(observation("sha256:" + Sha256.encode("changed")));
		assertTrue(first[3].name == "source-configuration" && first[3].revision != changed[3].revision,
			"a source-affecting configuration change should change its revision domain");

		final exactImplementation = OcamlTargetReuseContract.revisionComponents(observation(null, false, false, false,
			"sha256:" + Sha256.encode("target implementation"), true));
		assertTrue(exactImplementation[4].name == "target-implementation",
			"an exact target source identity should replace the provisional implementation component");
	}

	static function testFailClosedBlockers():Void {
		final baseline = OcamlTargetReuseContract.blockers(observation());
		assertTrue(baseline.length == 2, "disabled reuse and the missing exact target identity should block the baseline");
		assertTrue(baseline.contains("reflaxe.ocaml:target-reuse-disabled"), "production reuse should require an explicit opt-in");
		assertTrue(baseline.contains("reflaxe.ocaml:target-implementation-authority-incomplete"),
			"the package/pipeline candidate must not pretend to be complete implementation identity");
		assertTrue(OcamlTargetReuseContract.blockers(observation(null, false, false, false, "sha256:" + Sha256.encode("target implementation"), true))
			.length == 0,
			"complete source inputs and an exact implementation identity should clear target-owned blockers");

		final evidence = OcamlTargetReuseContract.blockers(observation(null, true, true, true, null, false, false));
		assertTrue(evidence.contains("reflaxe.ocaml:progress-or-telemetry-enabled"), "progress or telemetry should block replay");
		assertTrue(evidence.contains("reflaxe.ocaml:lowering-report-enabled"), "lowering reports should block replay");
		assertTrue(evidence.contains("reflaxe.ocaml:lifecycle-trace-enabled"), "lifecycle traces should block replay");
		assertTrue(evidence.contains("reflaxe.ocaml:transactional-output-disabled"), "non-transactional output should block replay");
		final mli = OcamlTargetReuseContract.blockers(observation(null, false, false, false, "sha256:" + Sha256.encode("target implementation"), true, true,
			true));
		assertTrue(mli.contains("reflaxe.ocaml:mli-generation-enabled"), "interface generation should block first-rung replay");
	}

	static function main():Void {
		testStableComponents();
		testFailClosedBlockers();
		Sys.println("REFLAXE_OCAML_TARGET_REUSE_CONTRACT:PASS");
	}
}
