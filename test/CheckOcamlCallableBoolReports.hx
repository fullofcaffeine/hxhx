import reflaxe.ocaml.tooling.ReflaxeOcamlInspection;
import reflaxe.ocaml.tooling.ReflaxeOcamlCallableViewInspection;
import reflaxe.ocaml.reports.OcamlCallableCallReport;
import reflaxe.ocaml.reports.OcamlCallableViewInventory;
import reflaxe.ocaml.reports.OcamlGenericCallReport.sequence;
import reflaxe.ocaml.reports.OcamlReportJson.encode;
import reflaxe.ocaml.lowered.OcamlCallableValueOperation;
import reflaxe.ocaml.lowered.OcamlCallableViewRuntime;

/** Real Boolean crossings must own both helpers; an unrelated conversion cannot supply their evidence. */
@:access(reflaxe.ocaml.tooling.ReflaxeOcamlInspection)
class CheckOcamlCallableBoolReports {
	public static function main():Void {
		final arguments = Sys.args();
		if (arguments.length != 1)
			throw "Expected the generated Boolean callback lowering report.";
		// Untrusted JSON stays at the decoder boundary. All operation and helper
		// assertions below use the production reader's validated records.
		final value:Dynamic = haxe.Json.parse(sys.io.File.getContent(arguments[0]));
		final representations = ReflaxeOcamlInspection.inspectRepresentations(value, "Boolean callback report", 0, []);
		final calls = ReflaxeOcamlInspection.inspectCalls(value, representations);
		final report = reflaxe.ocaml.tooling.ReflaxeOcamlCallableViewInspection.inspect(Reflect.field(value, "callableViews"), representations.decisions,
			ReflaxeOcamlInspection.FUNCTION_PLAN_PIPELINE_REVISION, calls.calls, calls.boundaries);
		final operations:Array<OcamlCallableValueOperation> = [];
		for (call in calls.calls)
			if (call.sourceFieldName == "preserve") {
				if (call.arguments.length != 1 || call.arguments[0].callbackArgument == null)
					throw "Boolean callback argument has no preparation record.";
				operations.push(argumentFromReport(call.arguments[0].callbackArgument).operation);
			}
		if (operations.length != 2)
			throw "Boolean report must cover a local argument and a call-produced argument.";
		final boundary = Lambda.find(calls.boundaries, boundary -> boundary.sourceFieldName == "booleanCallback");
		if (boundary == null || boundary.callbackReturns == null || boundary.callbackReturns.length != 1)
			throw "Boolean report lost its converted method return.";
		operations.push(reflaxe.ocaml.lowered.OcamlCallableReturnContract.operation(returnFromReport(boundary.callbackReturns[0])));
		final expectedIds:Array<String> = [];
		for (operation in operations) {
			if (Std.string(operation.conversion) != "AdaptFunction([BoxBoolean],UnboxBoolean)")
				throw "Boolean callback crossing lost its argument/result direction.";
			final uses = valueOccurrences(operation);
			if (uses.map(use -> use.exactSymbol).join(",") != "HxRuntime.box_bool,HxRuntime.unbox_bool_or_obj")
				throw "Boolean callback crossing does not own exactly its box and unbox helpers.";
			for (use in uses)
				expectedIds.push(use.requirementId);
		}
		final requirements:Map<String, Dynamic> = [];
		for (entry in sequence(Reflect.field(value, "runtimeRequirements")))
			requirements.set(reflaxe.ocaml.reports.OcamlGenericCallReport.text(Reflect.field(entry, "id")), entry);
		function check(selected:Map<String, Dynamic>):Array<String> {
			return reflaxe.ocaml.tooling.ReflaxeOcamlCallableViewInspection.validateRuntime(report, selected, calls.calls, calls.boundaries);
		}
		final actual = check(requirements);
		expectedIds.sort(Reflect.compare);
		actual.sort(Reflect.compare);
		if (actual.join(",") != expectedIds.join(",") || expectedIds.length != 6)
			throw "Boolean callback inventory lost an argument or return helper.";
		for (id in expectedIds) {
			final missing = requirements.copy();
			missing.remove(id);
			reject(() -> check(missing));
			final foreign = requirements.copy();
			final changed:Dynamic = haxe.Json.parse(encode(requirements.get(id)));
			Reflect.setField(changed, "decisionId", "foreign-callback");
			foreign.set(id, changed);
			reject(() -> check(foreign));
		}
		Sys.println("OCAML_CALLBACK_BOOL_HELPERS:PASS");
	}

	static function reject(action:Void->Void):Void {
		var rejected = false;
		try
			action()
		catch (error:haxe.Exception) {
			if (!StringTools.contains(error.message, "missing or changed runtime evidence"))
				throw error;
			rejected = true;
		}
		if (!rejected)
			throw "Boolean callback accepted missing or foreign helper ownership.";
	}
}
