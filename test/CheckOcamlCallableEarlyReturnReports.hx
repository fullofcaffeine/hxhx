import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;
import reflaxe.ocaml.reports.OcamlGenericCallReport.sequence;
import reflaxe.ocaml.reports.OcamlReportJson.encode;

/** Prepared callback returns must remain joined to the control transfers that carry them. */
@:access(reflaxe.ocaml.tooling.ReflaxeOcamlInspection)
class CheckOcamlCallableEarlyReturnReports {
	static function main():Void {
		final arguments = Sys.args();
		if (arguments.length != 1)
			throw "Expected the generated lowering report path.";
		final json = sys.io.File.getContent(arguments[0]);
		final value:Dynamic = haxe.Json.parse(json);
		final representations = ReflaxeOcamlInspection.inspectRepresentations(value, "callback-control-report", 0, []);
		final calls = ReflaxeOcamlInspection.inspectCalls(value, representations);
		reflaxe.ocaml.tooling.ReflaxeOcamlCallableViewInspection.inspect(value.callableViews, representations.decisions,
			ReflaxeOcamlInspection.FUNCTION_PLAN_PIPELINE_REVISION, calls.calls, calls.boundaries);
		final arrays = ReflaxeOcamlInspection.inspectArrayLiteralProducers(value, representations);
		final targets = ReflaxeOcamlInspection.inspectControlTargets(value);
		ReflaxeOcamlInspection.inspectControls(value, representations, arrays, targets);
		// Mutations below change only control records. Reuse independently
		// validated, unchanged inventories instead of decoding them thirty times.
		for (name in ["branch", "guarded", "aliased", "forwarded", "captured"])
			for (mutation in ["missing", "revision", "body", "source", "other-return", "unprepared"]) {
				// JSON is deliberately untrusted here. Production decoders narrow it
				// before the shared return/control relationship check.
				final changed:Dynamic = haxe.Json.parse(json);
				final boundary:Dynamic = required(sequence(changed.callableBoundaries), value -> value.sourceFieldName == name);
				final matches = sequence(changed.controls).filter(control -> control.functionId == boundary.functionId
					&& control.kind == "return");
				if (matches.length != 1)
					throw "Expected one early callback transfer in " + name;
				final control:Dynamic = matches[0];
				if (control.payload.conversion != "box-and-recover-callable-view")
					throw "Callback transfer used an ordinary function representation.";
				var expected:String;
				switch (mutation) {
					case "missing":
						Reflect.setField(control.payload, "callbackReturnId", null);
						expected = "missing-return";
					case "revision":
						Reflect.setField(control.payload, "callbackReturnRevision", "sha256:" + haxe.crypto.Sha256.encode("foreign"));
						expected = "missing-return";
					case "body":
						for (entry in sequence(changed.controls))
							if (entry.functionId == control.functionId)
								Reflect.setField(entry, "bodyRevision", "foreign-body");
						expected = "foreign-binding";
					case "source":
						Reflect.setField(control.source, "file", "Foreign.hx");
						expected = "foreign-return";
					case "other-return":
						final other = required(sequence(boundary.callbackReturns), returned -> returned.id != control.payload.callbackReturnId);
						Reflect.setField(control.payload, "callbackReturnId", other.id);
						Reflect.setField(control.payload, "callbackReturnRevision", other.revision);
						expected = "foreign-return";
					case "unprepared":
						Reflect.setField(control.payload, "conversion", "box-and-recover-typed-function-result");
						Reflect.setField(control.payload, "callbackReturnId", null);
						Reflect.setField(control.payload, "callbackReturnRevision", null);
						expected = "prepared view payload";
					case _:
						throw "Unknown callback control mutation.";
				}
				Reflect.setField(changed, "controlRevision", "sha256:" + haxe.crypto.Sha256.encode(encode({
					targets: changed.controlTargets,
					decisions: changed.controls,
					catchChains: changed.controlCatches
				})));
				var rejected = false;
				try
					ReflaxeOcamlInspection.inspectControls(changed, representations, arrays, targets)
				catch (error:haxe.Exception) {
					if (!StringTools.contains(error.message, expected))
						throw mutation + " failed for another reason: " + error.message;
					rejected = true;
				}
				if (!rejected)
					throw "Public inspection accepted a changed callback transfer.";
			}
		final absent:Dynamic = required(sequence(value.callableBoundaries), boundary -> boundary.sourceFieldName == "unavailable");
		if (absent.callbackReturnCount != 0 || sequence(absent.callbackReturns).length != 0)
			throw "Throwing callback factory must retain a completed empty return inventory.";
		for (mutation in [
			"missing-count",
			"negative-count",
			"text-count",
			"wrong-count",
			"missing-inventory",
			"deleted-return"
		]) {
			final changed:Dynamic = haxe.Json.parse(json);
			final boundary:Dynamic = required(sequence(changed.callableBoundaries),
				entry -> entry.sourceFieldName == (mutation == "deleted-return" ? "branch" : "unavailable"));
			var expected:String;
			switch (mutation) {
				case "missing-count":
					Reflect.deleteField(boundary, "callbackReturnCount");
					expected = "missing field";
				case "negative-count":
					Reflect.setField(boundary, "callbackReturnCount", -1);
					expected = "nonnegative integer";
				case "text-count":
					Reflect.setField(boundary, "callbackReturnCount", "0");
					expected = "nonnegative integer";
				case "wrong-count":
					Reflect.setField(boundary, "callbackReturnCount", 1);
					expected = "incomplete return";
				case "missing-inventory":
					Reflect.setField(boundary, "callbackReturns", null);
					expected = "no producing return";
				case "deleted-return":
					sequence(boundary.callbackReturns).pop();
					expected = "incomplete return";
				case _:
					throw "Unknown return inventory mutation.";
			}
			Reflect.setField(changed, "callRevision",
				"sha256:" + haxe.crypto.Sha256.encode(encode({calls: changed.calls, callableBoundaries: changed.callableBoundaries})));
			var rejected = false;
			try
				ReflaxeOcamlInspection.inspectCalls(changed, representations)
			catch (error:haxe.Exception) {
				if (!StringTools.contains(error.message, expected))
					throw mutation + " failed for another reason: " + error.message;
				rejected = true;
			}
			if (!rejected)
				throw "Public inspection accepted " + mutation;
		}
		Sys.println("OCAML_CALLBACK_EARLY_RETURNS:PASS");
	}

	static function required(values:Array<Dynamic>, predicate:Dynamic->Bool):Dynamic {
		return Lambda.find(values, predicate) ?? throw "Missing independently expected callback occurrence.";
	}
}
