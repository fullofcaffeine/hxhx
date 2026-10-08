import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;
import reflaxe.ocaml.tooling.ReflaxeOcamlCallableViewInspection;
import reflaxe.ocaml.reports.OcamlGenericCallReport.sequence;

/** Exercise actual generated reports and independently corrupt the relationships between their records. */
@:access(reflaxe.ocaml.tooling.ReflaxeOcamlInspection)
class CheckOcamlCallableInspection {
	public static function main():Void {
		final arguments = Sys.args();
		if (arguments.length != 1)
			throw "Expected the generated lowering report path.";
		verify(sys.io.File.getContent(arguments[0]));
		Sys.println("OCAML_CALLABLE_INSPECTION:PASS");
	}

	/** Every mutation starts from the same valid compiler output and must fail for its intended relationship. */
	public static function verify(json:String):Void {
		inspect(haxe.Json.parse(json));
		for (mutation in [
			"argument-slot",
			"argument-body",
			"argument-local",
			"invocation-source",
			"invocation-local",
			"invocation-missing",
			"return-owner",
			"return-call",
			"parameter-owner",
			"missing-return",
			"missing-callback-field"
		]) {
			// Dynamic is test-only untrusted JSON. The production reader narrows it
			// before checking declarations, source occurrences, and native carriers.
			final changed:Dynamic = haxe.Json.parse(json);
			final calls = sequence(Reflect.field(changed, "calls"));
			final boundaries = sequence(Reflect.field(changed, "callableBoundaries"));
			final prepared = required(calls,
				call -> Lambda.exists(sequence(Reflect.field(call, "arguments")), value -> Reflect.field(value, "callbackArgument") != null));
			final argument = required(sequence(prepared.arguments), value -> Reflect.field(value, "callbackArgument") != null);
			final invoked = required(calls,
				call -> Reflect.field(call, "callbackInvocation") != null
					&& Reflect.field(Reflect.field(Reflect.field(call, "callbackInvocation"), "input"), "kind") == "existing-view");
			final returning = required(boundaries, value -> Reflect.field(value, "callbackReturns") != null);
			var expected:String;
			switch (mutation) {
				case "argument-slot":
					Reflect.setField(argument.callbackArgument, "id", "another-call:callback-argument:0");
					expected = "another call slot";
				case "argument-body":
					Reflect.setField(argument.callbackArgument.binding, "bodyRevision", "another-body");
					expected = "another call slot";
				case "argument-local":
					Reflect.setField(argument.callbackArgument.input.reference, "localId", "lexical-local-v1:" + haxe.crypto.Sha256.encode("foreign-local"));
					expected = "selected storage";
				case "invocation-source":
					Reflect.setField(invoked.callbackInvocation.source, "min", 0);
					expected = "computed call signature";
				case "invocation-local":
					Reflect.setField(invoked.callbackInvocation.input.reference, "localId", "lexical-local-v1:" + haxe.crypto.Sha256.encode("foreign-local"));
					expected = "selected storage";
				case "invocation-missing":
					Reflect.setField(invoked, "callbackInvocation", null);
					expected = "lost its recursive signature";
				case "return-owner":
					Reflect.setField(returning, "bodyRevision", "another-body");
					expected = "foreign-binding";
				case "return-call":
					final forwarding = required(boundaries,
						value -> Reflect.field(value, "callbackReturns") != null
							&& Reflect.field(Reflect.field(sequence(value.callbackReturns)[0], "input"), "kind") == "call-result");
					final returned = sequence(forwarding.callbackReturns)[0];
					final producer = required(calls, call -> Reflect.field(call, "id") == Reflect.field(returned.input, "callId"));
					Reflect.setField(producer, "bodyRevision", "another-body");
					expected = "actual call result";
				case "parameter-owner":
					final preserve = required(boundaries, value -> Reflect.field(value, "sourceFieldName") == "preserve");
					Reflect.setField(preserve, "id", "foreign-boundary");
					expected = "declared callable owner";
				case "missing-return":
					Reflect.setField(returning, "callbackReturns", null);
					expected = "no producing return";
				case "missing-callback-field":
					Reflect.deleteField(argument, "callableView");
					expected = "missing field";
				case _:
					throw "Unknown inspection mutation.";
			}
			// Keep the outer digest consistent so it cannot hide a missing
			// declaration, source, or storage relationship check.
			Reflect.setField(changed, "callRevision", "sha256:" + haxe.crypto.Sha256.encode(reflaxe.ocaml.reports.OcamlReportJson.encode({
				calls: Reflect.field(changed, "calls"),
				callableBoundaries: Reflect.field(changed, "callableBoundaries")
			})));
			var rejected = false;
			try
				inspect(changed)
			catch (error:haxe.Exception) {
				if (!StringTools.contains(error.message, expected))
					throw mutation + " failed for another reason: " + error.message;
				rejected = true;
			}
			if (!rejected)
				throw "Callback inspection accepted " + mutation;
		}
	}

	static function inspect(value:Dynamic):Void {
		final representations = ReflaxeOcamlInspection.inspectRepresentations(value, "callback-report", 0, []);
		final inventory = ReflaxeOcamlInspection.inspectCalls(value, representations);
		reflaxe.ocaml.tooling.ReflaxeOcamlCallableViewInspection.inspect(Reflect.field(value, "callableViews"), representations.decisions,
			ReflaxeOcamlInspection.FUNCTION_PLAN_PIPELINE_REVISION, inventory.calls, inventory.boundaries);
	}

	static function required(values:Array<Dynamic>, predicate:Dynamic->Bool):Dynamic {
		return Lambda.find(values, predicate) ?? throw "Generated callback fixture lacks an independently expected occurrence.";
	}
}
