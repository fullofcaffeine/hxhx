package reflaxe.ocaml.lifecycle;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.lifecycle.SemanticLifecycleTraceEvent;

/** Writes bounded, path-free evidence for place operations that crossed preprocessing. */
class OcamlSemanticLifecycleTraceWriter {
	public static inline final FILE_NAME = "ocaml_semantic_lifecycle_trace.json";

	/** Writes only boundaries where the OCaml place family actually existed. */
	public static function write(outputDirectory:String, programRevision:String, pipelineRevision:String, events:Array<SemanticLifecycleTraceEvent>,
			functionFilter:Null<String> = null):Void {
		final active = events.filter(event -> event.artifactIds.length > 0
			&& (functionFilter == null || functionFilter.length == 0 || event.functionId.indexOf(functionFilter) >= 0))
			.map(event -> ({
				functionId: event.functionId,
				programRevision: event.programRevision,
				pipelineRevision: event.pipelineRevision,
				preprocessorId: event.preprocessorId,
				phase: event.phase,
				bodyRevision: event.bodyRevision,
				familyId: event.familyId,
				action: event.action,
				artifactIds: event.artifactIds.copy()
			}));
		for (event in active)
			event.artifactIds.sort(Reflect.compare);
		active.sort((left,
				right) -> Reflect.compare([left.functionId, left.preprocessorId, left.phase, left.familyId].join("\n"),
				[right.functionId, right.preprocessorId, right.phase, right.familyId].join("\n")));
		final canonical = haxe.Json.stringify(active);
		final report = {
			schemaVersion: 1,
			model: "reflaxe-ocaml-semantic-lifecycle",
			programRevision: programRevision,
			pipelineRevision: pipelineRevision,
			functionFilter: functionFilter,
			traceRevision: "sha256:" + Sha256.encode(canonical),
			activeEventCount: active.length,
			events: active
		};
		sys.io.File.saveContent(Path.join([outputDirectory, FILE_NAME]), haxe.Json.stringify(report, null, "  ") + "\n");
	}
}
#end
