import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;
import reflaxe.ocaml.reports.OcamlCallableCallReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport.sequence;
import reflaxe.ocaml.reports.OcamlReportJson.encode;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract;

/** A valid return fingerprint cannot substitute for ownership of the returned local. */
@:access(reflaxe.ocaml.tooling.ReflaxeOcamlInspection)
class CheckOcamlCallableReturnAliasReports {
	static function main():Void {
		final arguments = Sys.args();
		if (arguments.length != 1)
			throw "Expected the generated lowering report path.";
		final json = sys.io.File.getContent(arguments[0]);
		inspect(haxe.Json.parse(json));
		for (name in ["fromParameter", "fromStatic", "fromCall"])
			for (foreign in [false, true]) {
				// Deliberate JSON corruption stays inside this test boundary.
				final changed:Dynamic = haxe.Json.parse(json);
				final entries = returns(changed, name);
				if (entries.length != 1)
					throw "Expected one returned alias in " + name;
				final selected = returnFromReport(entries[0]);
				final replacement = switch (selected.input) {
					case LocalView(reference, layout):
						final foreignName = name == "fromCall" ? "fromStatic" : "fromCall";
						final localId = foreign ? switch (returnFromReport(returns(changed, foreignName)[0]).input) {
							case LocalView(other, _): other.localId;
							case _: throw "Expected another real returned local.";
						} : "lexical-local-v1:" + haxe.crypto.Sha256.encode("absent-returned-local");
						if (localId == reference.localId)
							throw "Return corruption did not change local ownership.";
						LocalView({
							localId: localId,
							representationId: reference.representationId,
							representationRevision: reference.representationRevision,
							semanticTypeId: reference.semanticTypeId,
							domain: reference.domain
						}, layout);
					case _: throw "Expected a selected local callback return in " + name;
				};
				// Recompute both digests. Rejection must come from the actual body/storage
				// relationship, not an incidental stale checksum.
				entries[0] = returnToReport(seal({
					binding: selected.binding,
					boundary: selected.boundary,
					ordinal: selected.ordinal,
					source: selected.source,
					input: replacement
				}));
				Reflect.setField(changed, "callRevision", "sha256:" + haxe.crypto.Sha256.encode(encode({
					calls: Reflect.field(changed, "calls"),
					callableBoundaries: Reflect.field(changed, "callableBoundaries")
				})));
				var rejected = false;
				try
					inspect(changed)
				catch (error:haxe.Exception) {
					if (!StringTools.contains(error.message, "selected storage"))
						throw error;
					rejected = true;
				}
				if (!rejected)
					throw "Report accepted a returned local from outside its final body.";
			}
		Sys.println("OCAML_CALLBACK_RETURN_ALIASES:PASS");
	}

	static function returns(report:Dynamic, name:String):Array<Dynamic> {
		final boundary = Lambda.find(sequence(Reflect.field(report, "callableBoundaries")), value -> Reflect.field(value, "sourceFieldName") == name);
		if (boundary == null)
			throw "Missing returned-alias declaration: " + name;
		return sequence(Reflect.field(boundary, "callbackReturns"));
	}

	static function inspect(value:Dynamic):Void {
		final representations = ReflaxeOcamlInspection.inspectRepresentations(value, "callback-alias-report", 0, []);
		final inventory = ReflaxeOcamlInspection.inspectCalls(value, representations);
		reflaxe.ocaml.tooling.ReflaxeOcamlCallableViewInspection.inspect(Reflect.field(value, "callableViews"), representations.decisions,
			ReflaxeOcamlInspection.FUNCTION_PLAN_PIPELINE_REVISION, inventory.calls, inventory.boundaries);
	}
}
