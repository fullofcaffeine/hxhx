import haxe.macro.Context;
import reflaxe.ocaml.lowered.OcamlMethodDispatchRootPlan;

/** Protects method admission when cheap data-field rejection precedes receiver inspection. */
class CheckMethodOccurrences {
	public static function run():Void {
		final cases:Array<{expression:String, expected:Bool, call:Bool}> = [
			{expression: "(null : MethodOccurrenceCases.NamedView).read()", expected: true, call: true},
			{expression: "(null : MethodOccurrenceCases.NamedView).read", expected: true, call: false},
			{expression: "(null : MethodOccurrenceCases.StructuralView).read()", expected: true, call: true},
			{expression: "(null : MethodOccurrenceCases.StructuralView).read", expected: true, call: false},
			{expression: "(null : MethodOccurrenceCases.CallbackRecord).read()", expected: false, call: true},
			{expression: "(null : MethodOccurrenceCases.CallbackRecord).read", expected: false, call: false},
			{expression: "(null : MethodOccurrenceCases.DataRecord).read", expected: false, call: false},
			{expression: "new MethodOccurrenceCases.Source().read()", expected: false, call: true},
			{expression: "new MethodOccurrenceCases.Source().read", expected: false, call: false},
			{expression: "MethodOccurrenceCases.Source.staticRead()", expected: false, call: true},
			{expression: "(null : Iterator<Int>).next()", expected: false, call: true},
			{expression: "(null : haxe.Constraints.IMap<String, Int>).get(\"x\")", expected: false, call: true}
		];
		for (index in 0...cases.length) {
			final test = cases[index];
			final expression = Context.typeExpr(Context.parse(test.expression, Context.currentPos()));
			final use = OcamlMethodDispatchRootPlan.occurrence(expression);
			if ((use != null) != test.expected)
				Context.fatalError("wrong method admission for case " + index, Context.currentPos());
			if (use != null && (use.field.name != "read" || (use.arguments != null) != test.call))
				Context.fatalError("wrong selected method or operation for case " + index, Context.currentPos());
		}
	}
}
