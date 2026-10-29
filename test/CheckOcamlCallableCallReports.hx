import reflaxe.ocaml.lowered.OcamlCallableArgumentPlan;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.reports.OcamlCallableCallReport;
import reflaxe.ocaml.reports.OcamlReportJson.encode;

/** Exercise the same JSON boundary in macro planning and in the standalone report reader. */
class CheckOcamlCallableCallReports {
	public static function main():Void {
		final layout = describe(FunctionValue([Integer], Integer));
		final binding:reflaxe.ocaml.lowered.OcamlFunctionPlanBinding = {
			functionId: "returning-function",
			bodyRevision: "final-body",
			programRevision: "program",
			pipelineRevision: "pipeline"
		};
		for (input in [
			Producer(FreshLiteral, layout),
			Producer(StaticDeclaration("ordinary-method"), layout),
			Parameter(0),
			LocalView({
				localId: "lexical-local-v1:" + haxe.crypto.Sha256.encode("returned-local"),
				representationId: "representation:" + layout.semanticTypeId + ":internal-value",
				representationRevision: "sha256:" + haxe.crypto.Sha256.encode("representation"),
				semanticTypeId: layout.semanticTypeId,
				domain: InternalValue
			}, layout),
			CallResult("actual-call", {
				calleeId: "factory",
				layout: describe(FunctionValue([], layout.shape)),
				programRevision: "program",
				pipelineRevision: "pipeline"
			})
		]) {
			final decision = seal({
				binding: binding,
				ordinal: 0,
				source: {file: "Example.hx", min: 20, max: 40},
				input: input,
				boundary: {
					calleeId: "returning-method",
					layout: describe(FunctionValue([layout.shape], layout.shape)),
					functionId: binding.functionId,
					bodyRevision: binding.bodyRevision,
					programRevision: binding.programRevision,
					pipelineRevision: binding.pipelineRevision
				}
			});
			verifyReturn(encode(returnToReport(decision)));
		}
		final argument:OcamlCallableArgumentPlan = {
			input: RawOrigin(FreshLiteral),
			operation: {
				id: "call:callback-argument:0",
				role: ArgumentValue,
				binding: binding,
				source: {file: "Example.hx", min: 10, max: 19},
				origin: FreshLiteral,
				inputLayout: describe(FunctionValue([DynamicValue], DynamicValue)),
				outputLayout: layout,
				conversion: AdaptFunction([BoxValue], UnboxValue)
			}
		};
		verifyArgument(encode(argumentToReport(argument)));
		Sys.println("OCAML_CALLABLE_CALL_REPORT:PASS");
	}

	/** Real planner decisions must survive decoding without changing the producer or native conversion. */
	public static function verifyReturn(json:String):Void {
		if (encode(returnToReport(returnFromReport(haxe.Json.parse(json)))) != json)
			throw "Callback return report did not preserve the selected decision.";
		for (mutation in [
			"body",
			"source",
			"ordinal",
			"callee",
			"tag",
			"unused",
			"adapter",
			"extra",
			"native-evidence"
		]) {
			// These deliberate edits model untrusted JSON. No untyped value escapes
			// the decoder under test into the compiler's ordinary domain logic.
			final changed:Dynamic = haxe.Json.parse(json);
			switch (mutation) {
				case "body":
					Reflect.setField(changed.binding, "bodyRevision", "foreign-body");
				case "source":
					Reflect.setField(changed.source, "min", -1);
				case "ordinal":
					Reflect.setField(changed, "ordinal", 1);
				case "callee":
					Reflect.setField(changed.boundary, "calleeId", "foreign-callee");
				case "tag":
					Reflect.setField(changed.input, "kind", "unknown");
				case "unused":
					Reflect.setField(changed.input, "calleeId", "unexpected-producer");
				case "adapter":
					Reflect.setField(changed.adapter, "outputRevision", "changed");
				case "native-evidence":
					Reflect.setField(changed, "unsafeOperations", [{}]);
				case "extra":
					Reflect.setField(changed, "unchecked", true);
			}
			reject(() -> returnFromReport(changed));
		}
	}

	/** Check source and conversion corruption while leaving enclosing call ownership to its join tests. */
	public static function verifyArgument(json:String):Void {
		if (encode(argumentToReport(argumentFromReport(haxe.Json.parse(json)))) != json)
			throw "Callback argument report did not preserve preparation.";
		for (mutation in ["source", "tag", "extra", "adapter", "missing", "native-evidence"]) {
			final changed:Dynamic = haxe.Json.parse(json);
			switch (mutation) {
				case "source":
					Reflect.setField(changed.source, "max", -1);
				case "tag":
					Reflect.setField(changed.input, "kind", "unknown");
				case "native-evidence":
					Reflect.setField(changed, "unsafeOperations", [{}]);
				case "extra":
					Reflect.setField(changed, "unchecked", true);
				case "adapter":
					Reflect.setField(changed.adapter, "inputRevision", "changed");
				case "missing":
					Reflect.deleteField(changed, "binding");
			}
			reject(() -> argumentFromReport(changed));
		}
	}

	static function reject(action:Void->Void):Void {
		var rejected = false;
		try
			action()
		catch (_:haxe.Exception)
			rejected = true;
		if (!rejected)
			throw "Changed callback call evidence was accepted.";
	}
}
