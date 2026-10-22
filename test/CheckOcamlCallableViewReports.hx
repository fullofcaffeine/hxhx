import reflaxe.ocaml.lowered.OcamlGenericCallConversion;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.reports.OcamlCallableViewReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport;
import reflaxe.ocaml.reports.OcamlReportJson.encode;

/** Independent wire examples check direction, explicit Dynamic, and malformed report rejection. */
class CheckOcamlCallableViewReports {
	public static function main():Void {
		verify();
	}

	/** Inspect an actual compiler-selected occurrence outside the macro host, then corrupt its evidence. */
	public static function verifyLocalReport(json:String):Void {
		final selected = localFromReport(haxe.Json.parse(json));
		if (encode(localToReport(selected)) != json)
			throw "Callback occurrence report changed its sealed decision.";
		for (mutation in ["body", "source", "local", "role", "revision", "origin", "extra"]) {
			// Deliberate JSON corruption at the untrusted report boundary.
			final changed:Dynamic = haxe.Json.parse(json);
			switch (mutation) {
				case "body":
					Reflect.setField(Reflect.field(changed, "binding"), "bodyRevision", "foreign-body");
				case "source":
					Reflect.setField(Reflect.field(changed, "source"), "min", -1);
				case "local":
					Reflect.setField(Reflect.field(changed, "output"), "localId", "123");
				case "role":
					Reflect.setField(changed, "role", "read");
				case "revision":
					Reflect.setField(changed, "revision", "sha256:stale");
				case "origin":
					Reflect.setField(Reflect.field(changed, "input"), "kind", "returned-function");
				case "extra":
					Reflect.setField(Reflect.field(changed, "binding"), "unchecked", true);
			}
			reject(() -> localFromReport(changed));
		}
		Sys.println("OCAML_CALLABLE_OCCURRENCE_REPORT:PASS");
	}

	public static function verify():Void {
		final source = describe(FunctionValue([DynamicValue], DynamicValue));
		final destination = describe(FunctionValue([Boolean], Boolean));
		final report = adapterToReport(source, destination, AdaptFunction([BoxBoolean], UnboxBoolean));
		final decoded = adapterFromReport(haxe.Json.parse(encode(report)));
		if (decoded.input.semanticTypeId != "(Dynamic)->Dynamic"
			|| decoded.output.semanticTypeId != "(Bool)->Bool"
			|| Std.string(decoded.conversion) != "AdaptFunction([BoxBoolean],UnboxBoolean)")
			throw "Callback report lost its typed direction.";
		final expected = '{"children":[{"children":[],"kind":"dynamic","parameter":null},{"children":[],"kind":"dynamic","parameter":null}],"kind":"function","parameter":null}';
		if (encode(report.input) != expected)
			throw "Callback report has changed its explicit Dynamic wire format.";
		for (shape in [
			FunctionValue([], EffectOnly),
			FunctionValue([NullableInteger, NullableBoolean, Text(true)], Text(false)),
			FunctionValue([FunctionValue([Integer], Integer)], FunctionValue([DynamicValue], DynamicValue))
		]) {
			final restored = callableShapeFromReport(haxe.Json.parse(encode(callableShapeToReport(shape))));
			if (shapeId(restored) != shapeId(shape))
				throw "Recursive callback report lost its layout.";
		}
		reject(() -> adapterToReport(source, destination, Identity));
		reject(() -> adapterToReport(destination, source, AdaptFunction([BoxBoolean], UnboxBoolean)));
		for (shape in [
			DynamicValue,
			FunctionValue([Erased("T")], Integer),
			FunctionValue([EffectOnly], Integer),
			FunctionValue([ArrayValue(Integer)], Integer),
			FunctionValue([NominalValue("C", "r", false)], Integer)
		])
			reject(() -> callableShapeToReport(shape));
		for (json in [
			'{"kind":"dynamic","parameter":null,"children":[]}',
			'{"kind":"function","parameter":null,"children":[]}',
			'{"kind":"function","parameter":"T","children":[{"kind":"int","parameter":null,"children":[]}]}',
			'{"kind":"function","parameter":null,"children":[{"kind":"erased","parameter":"T","children":[]}]}',
			'{"kind":"function","parameter":null,"children":[{"kind":"dynamic","parameter":null,"children":[],"extra":1}]}',
			'{"kind":"function","parameter":null,"children":[{"kind":"dynamic","parameter":null,"children":[{}]}]}'
		])
			reject(() -> callableShapeFromReport(haxe.Json.parse(json)));
		// Test-only JSON mutation models a stale or hostile report at the input boundary.
		for (mutation in ["direction", "revision", "extra", "missing"]) {
			final changed:Dynamic = haxe.Json.parse(encode(report));
			switch (mutation) {
				case "direction":
					Reflect.setField(changed, "conversion", conversionToReport(Identity));
				case "revision":
					Reflect.setField(changed, "inputRevision", destination.revision);
				case "extra":
					Reflect.setField(changed, "extra", true);
				case "missing":
					Reflect.deleteField(changed, "output");
			}
			reject(() -> adapterFromReport(changed));
		}
		Sys.println("OCAML_CALLABLE_VIEW_REPORT:PASS");
	}

	static function reject(run:Void->Void):Void {
		var failed = false;
		try
			run()
		catch (_:haxe.Exception)
			failed = true;
		if (!failed)
			throw "Malformed callback report was accepted.";
	}
}
