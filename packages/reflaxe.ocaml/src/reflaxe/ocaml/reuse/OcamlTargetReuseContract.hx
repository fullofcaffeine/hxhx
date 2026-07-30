package reflaxe.ocaml.reuse;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.lifecycle.TargetReuseRevisionComponent;

/**
	Plain request facts used to build the first OCaml target-reuse observation.

	The values contain revisions and feature flags only. They deliberately exclude
	typed Haxe nodes, compiler contexts, output writers, target plans, and source
	bytes so the observation can never become an accidental cache payload.
**/
typedef OcamlTargetReuseObservation = {
	final packageVersion:String;
	final pipelineRevision:String;
	final sourceConfigurationRevision:String;
	final outputSchemaRevision:String;
	final runtimeInputRevision:String;
	final nativeSourceInputRevision:String;
	final targetImplementationRevision:Null<String>;
	final reuseEnabled:Bool;
	final transactionalOutputEnabled:Bool;
	final observationReportEnabled:Bool;
	final mliEnabled:Bool;
	final outputConfigured:Bool;
	final progressOrTelemetryEnabled:Bool;
	final loweringReportEnabled:Bool;
	final lifecycleTraceEnabled:Bool;
}

/**
	Defines the fail-closed identity currently offered by `reflaxe.ocaml`.

	This contract makes the target's known request inputs observable before
	whole-program OCaml preparation. Replay additionally requires an explicit
	opt-in, transactional output, and exact implementation, runtime, and native
	source identities. The blockers prevent a partial or diagnostic request from
	being mistaken for permission to skip target work.
**/
class OcamlTargetReuseContract {
	public static inline final NAMESPACE = "reflaxe.ocaml.target-source/v1";
	public static inline final IMPLEMENTATION_MODEL = "reflaxe-ocaml-target-implementation-candidate-v1";

	/** Returns sorted target-owned revisions without exposing their raw inputs. **/
	public static function revisionComponents(observation:OcamlTargetReuseObservation):Array<TargetReuseRevisionComponent> {
		final implementationCandidateRevision = revision(IMPLEMENTATION_MODEL, [
			required(observation.packageVersion, "package version"),
			required(observation.pipelineRevision, "pipeline revision")
		]);
		final implementationRevision = observation.targetImplementationRevision == null ? implementationCandidateRevision : requiredRevision(observation.targetImplementationRevision,
			"target implementation revision");
		final implementationName = observation.targetImplementationRevision == null ? "target-implementation-candidate" : "target-implementation";
		final components = [
			new TargetReuseRevisionComponent("artifact-output-schema", required(observation.outputSchemaRevision, "output schema revision")),
			new TargetReuseRevisionComponent("native-source-input", requiredRevision(observation.nativeSourceInputRevision, "native source input revision")),
			new TargetReuseRevisionComponent("runtime-input", requiredRevision(observation.runtimeInputRevision, "runtime input revision")),
			new TargetReuseRevisionComponent("source-configuration", required(observation.sourceConfigurationRevision, "source configuration revision")),
			new TargetReuseRevisionComponent(implementationName, implementationRevision)
		];
		components.sort((left, right) -> Reflect.compare(left.name, right.name));
		return components;
	}

	/**
		Returns stable reasons that exact source replay is not yet allowed.

		Report and telemetry modes are request-specific blockers because a replay
		would otherwise skip the target work that produces their evidence.
	**/
	public static function blockers(observation:OcamlTargetReuseObservation):Array<String> {
		final values = new Array<String>();
		if (!observation.reuseEnabled)
			values.push("reflaxe.ocaml:target-reuse-disabled");
		if (observation.targetImplementationRevision == null)
			values.push("reflaxe.ocaml:target-implementation-authority-incomplete");
		if (!observation.transactionalOutputEnabled)
			values.push("reflaxe.ocaml:transactional-output-disabled");
		if (observation.observationReportEnabled)
			values.push("reflaxe.ocaml:observation-report-enabled");
		if (observation.mliEnabled)
			values.push("reflaxe.ocaml:mli-generation-enabled");
		if (!observation.outputConfigured)
			values.push("reflaxe.ocaml:output-not-configured");
		if (observation.progressOrTelemetryEnabled)
			values.push("reflaxe.ocaml:progress-or-telemetry-enabled");
		if (observation.loweringReportEnabled)
			values.push("reflaxe.ocaml:lowering-report-enabled");
		if (observation.lifecycleTraceEnabled)
			values.push("reflaxe.ocaml:lifecycle-trace-enabled");
		values.sort(Reflect.compare);
		return values;
	}

	static function revision(model:String, values:Array<String>):String {
		return "sha256:" + Sha256.encode(Json.stringify([model, values]));
	}

	static function required(value:String, label:String):String {
		if (value == null || StringTools.trim(value).length == 0)
			throw 'OCaml target reuse $label must not be empty.';
		return StringTools.trim(value);
	}

	static function requiredRevision(value:String, label:String):String {
		final normalized = required(value, label);
		if (!~/^sha256:[0-9a-f]{64}$/.match(normalized))
			throw 'OCaml target reuse $label must be a lowercase SHA-256 revision.';
		return normalized;
	}
}
#end
