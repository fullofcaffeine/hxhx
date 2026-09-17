#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlTargetDefinition;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.lifecycle.ProgramRevision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlNativeEnumResultAdmission;

/** Checks conservative classification and graph closure before any call can consume it. */
class EnumAdmissionFixture {
	static function expectRejected(check:Void->Void, message:String):Void {
		var rejected = false;
		try {
			check();
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw message;
	}

	public static function run():Void {
		final owner = switch (Context.getType("EnumAdmissionCases")) {
			case TInst(reference, _): reference.get();
			case _: throw "expected fixture class";
		};
		final fields = owner.fields.get();
		final context = new CompilationContext();
		final target = OcamlTargetDefinition.create();
		target.compiler.setOptions(target.options);
		final registry = target.compiler.functionPlanRegistry;
		final catalog = @:privateAccess registry.nativeEnumResults;
		function prepare(reverse:Bool):Void {
			target.compiler.beginProgramRevision(new ProgramRevision("enum-admission-fixture", 1, fields.length));
			final ordered = fields.copy();
			if (reverse)
				ordered.reverse();
			for (field in ordered)
				catalog.add(owner, field, false, context);
			catalog.finish();
		}
		for (reverse in [false, true]) {
			prepare(reverse);
			for (field in fields) {
				final id = OcamlCallPlanner.calleeId(owner, field);
				final expected = ["direct", "forwarded", "alternateForwarded", "retained", "constructedLocal"].indexOf(field.name) >= 0;
				if ((catalog.candidate(id) != null) != expected)
					throw "unexpected enum admission classification: " + field.name;
				if ((catalog.exclusion(id) == null) != expected)
					throw "enum classification lost its exclusion reason: " + field.name;
				if (expected) {
					final original = ClassFieldHelper.findFuncData(field, owner, false);
					if (original == null)
						throw "expected a real function body";
					for (preprocess in [false, true]) {
						final data = original.clone();
						data.bindProgramRevision("enum-admission-fixture");
						if (preprocess && target.options.expressionPreprocessors != null)
							data.applyPreprocessors(target.compiler, target.options.expressionPreprocessors);
						catalog.requireFinal(data, context);
					}
					final corrupted = original.clone();
					corrupted.bindProgramRevision("enum-admission-fixture");
					// An unchecked cast is deliberate negative input at this compiler boundary.
					corrupted.setExpr(Context.typeExpr(macro(cast "wrong" : Payload)));
					expectRejected(() -> catalog.requireFinal(corrupted, context), "an unsupported final producer retained early enum approval");
					if (field.name == "forwarded") {
						final alternate = ClassFieldHelper.findFuncData(fields.filter(item -> item.name == "alternateForwarded")[0], owner, false);
						if (alternate == null || alternate.expr == null)
							throw "expected the independent alternate call body";
						corrupted.setExpr(alternate.expr);
						expectRejected(() -> catalog.requireFinal(corrupted, context), "a different exact callee retained early enum approval");
					}
				}
			}
			final scans = catalog.bodyScans;
			final edges = catalog.edgeVisits;
			for (_ in 0...10)
				for (field in fields)
					catalog.candidate(OcamlCallPlanner.calleeId(owner, field));
			if (catalog.bodyScans != scans || catalog.edgeVisits != edges)
				throw "catalog queries rescanned source or dependency edges";
			if (scans != fields.length || edges > fields.length)
				throw "enum source or graph preparation was not bounded";
		}
		registry.beginProgram("next-program");
		final previous = ClassFieldHelper.findFuncData(fields[0], owner, false);
		if (previous == null)
			throw "expected a previous request's body";
		final stale = previous.clone();
		stale.bindProgramRevision("enum-admission-fixture");
		expectRejected(() -> catalog.requireFinal(stale, context), "a new request accepted the previous body's comparison");
		for (field in fields)
			if (catalog.candidate(OcamlCallPlanner.calleeId(owner, field)) != null
				|| catalog.exclusion(OcamlCallPlanner.calleeId(owner, field)) != null)
				throw "a new request retained an enum candidate";
		if (catalog.bodyScans != 0 || catalog.edgeVisits != 0)
			throw "a new request retained classification counters";
		Sys.println("REFLAXE_OCAML_ENUM_ADMISSION:PASS");
	}
}
#end
