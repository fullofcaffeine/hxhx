#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.lifecycle.FunctionBodyRevision;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlanner;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
#end

/** Exercise the production planner's complete-use check before syntax can change local storage. */
class CheckOcamlCallableLocalSelection {
	#if macro
	public static function verify():Void {
		check(macro {
			var source:Dynamic->Dynamic = function(value:Dynamic):Dynamic return value;
			var first:Int->Dynamic = source;
			var second:Int->Dynamic = source;
			first(7);
			first == second;
		}, ["source", "first", "second"]);
		// Context.typeExpr leaves this unused input monomorph unresolved. A
		// Dynamic destination alone must not invent the producer's argument ABI.
		check(macro {
			var source:Dynamic->Dynamic = value -> value;
			var first:Int->Dynamic = source;
			var second:Int->Dynamic = source;
			first(7);
			first == second;
		}, []);
		check(macro {
			var source:Dynamic->Dynamic = function(value:Dynamic):Dynamic return value;
			var first:Int->Dynamic = source;
			first(7);
			Sys.println(source);
		}, []);
		check(macro {
			var source:Int->Int = function(value:Int):Int return value;
			var alias = source;
			var storage = new Array<Int->Int>();
			storage.push(alias);
			source(7);
		}, []);
		check(macro {
			var source:Int->Int = function(value:Int):Int return value;
			var alias = source;
			source = function(value:Int):Int return value + 1;
			alias(7);
		}, []);
		check(macro {
			var source:Int->Int = function(value:Int):Int return value;
			var alias = source;
			var captured = function():Int return source(7);
			alias(7);
			captured();
		}, ["captured"]);
		check(macro {
			var source:Int->Int = function(value:Int):Int return value;
			var alias = source;
			var erased:Dynamic = alias;
			source(7);
		}, []);
		check(macro {
			var source:Int->Int = function(value:Int):Int return value;
			var unknown:Null<Int->Int> = null;
			source == unknown;
		}, []);
		Sys.println("OCAML_CALLABLE_LOCAL_SELECTION:PASS");
	}

	/** Compare selected names only in tests; production decisions use stable lexical identities. */
	static function check(source:Expr, expected:Array<String>):Void {
		final body = Context.typeExpr(source);
		final binding:OcamlFunctionPlanBinding = {
			functionId: "callable-selection",
			programRevision: "callable-selection-program",
			bodyRevision: FunctionBodyRevision.initial(body).id,
			pipelineRevision: "callable-selection-pipeline"
		};
		final identities = LexicalLocalIdentityPlan.build(binding.functionId, body);
		final storage = OcamlLocalStoragePlanner.planExpression(body, identities);
		final registry = new OcamlRepresentationRegistry();
		registry.beginProgram(binding.programRevision);
		final plan = OcamlLocalRepresentationPlanner.planExpression(body, identities, storage, registry, binding);
		plan.requirePlanBinding(binding);
		final required = [
			for (reference in plan.references())
				if (registry.require(reference.representationId, binding.programRevision)
					.boxingPolicy == CallableIdentityView) {binding: binding, reference: reference}
		];
		final report = reflaxe.ocaml.reports.OcamlCallableViewInventory.build(required, plan.callableViewConversions());
		final json = reflaxe.ocaml.reports.OcamlReportJson.encode(report);
		final restored = reflaxe.ocaml.reports.OcamlCallableViewInventory.fromReport(haxe.Json.parse(json));
		if (reflaxe.ocaml.reports.OcamlReportJson.encode(restored) != json)
			throw "Production callback inventory did not survive inspection.";
		if (required.length > 0) {
			var rejected = false;
			try
				reflaxe.ocaml.reports.OcamlCallableViewInventory.build(required, [])
			catch (_:haxe.Exception)
				rejected = true;
			if (!rejected)
				throw "Selected callback locals lost all conversion evidence without rejection.";
		}
		final actual:Array<String> = [];
		final diagnostic:Array<String> = [];
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TVar(local, value):
					diagnostic.push(local.name
						+ ": "
						+ Std.string(reflaxe.ocaml.lowered.OcamlGenericCallConversion.callableShape(local.t))
						+ " <- "
						+ (value == null ? "none" : Std.string(reflaxe.ocaml.lowered.OcamlGenericCallConversion.callableShape(value.t)))
						+ " storage="
						+ Std.string(storage.decisionFor(identities.requireHostId(local.id).id)));
					final reference = plan.referenceFor(identities.requireHostId(local.id).id);
					if (reference != null
						&& registry.require(reference.representationId, binding.programRevision).boxingPolicy == CallableIdentityView)
						actual.push(local.name);
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		actual.sort(Reflect.compare);
		expected.sort(Reflect.compare);
		if (actual.join(",") != expected.join(",") || plan.callableViewConversionCount != expected.length)
			throw 'callback storage selection differs: expected $expected, got $actual\n'
				+ diagnostic.join("\n")
				+ "\n"
				+ TypedExprTools.toString(body, true);
	}
	#end
}
