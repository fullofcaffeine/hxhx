package backend.vm;

import backend.vm.NekoCatchPlan.NekoCatchCase;

/**
	Render one ordered dispatch for statement and expression handlers.

	Each ordinary handler first tests the original carrier. Only a failed test
	may read a real ValueException payload, once, into that handler's private
	temporary. A failed chain rethrows the original carrier without conversion.
**/
function render(plan:NekoCatchPlan, carrier:String, indent:String, temporary:Int->String, predicate:(String, TypedRuntimeTypeTarget) -> String,
		conversion:(NekoCatchCase, String) -> String, payload:(NekoCatchCase, String) -> String,
		body:(NekoCatchCase, String, String) -> Array<String>):Array<String> {
	final cases = plan.getCases();
	function next(index:Int, padding:String):Array<String> {
		if (index == cases.length)
			return [padding + "$rethrow(" + carrier + ");"];
		final entry = cases[index];
		final use = entry.use;
		if (use == null)
			throw "Neko catch emission lost its prepared implicit-use facts";
		switch (use.view) {
			case Carrier:
				return body(entry, carrier, padding);
			case BaseException:
				return body(entry, conversion(entry, carrier), padding);
			case ExceptionSubtype | OrdinaryValue:
				final value = use.view.match(OrdinaryValue) ? temporary(index) : carrier;
				final out = new Array<String>();
				if (value != carrier)
					out.push(padding + "var " + value + " = " + carrier + ";");
				var condition = predicate(carrier, use.target);
				if (use.view.match(OrdinaryValue))
					condition += " || ("
						+ predicate(carrier, new TypedRuntimeTypeTarget(Nominal(use.payload.getOwner())))
						+ " && { "
						+ value
						+ " = "
						+ payload(entry, carrier)
						+ "; "
						+ predicate(value, use.target)
						+ "; })";
				out.push(padding + "if (" + condition + ") {");
				for (line in body(entry, value, padding + "  "))
					out.push(line);
				out.push(padding + "} else {");
				for (line in next(index + 1, padding + "  "))
					out.push(line);
				out.push(padding + "}");
				return out;
		}
	}
	return next(0, indent);
}
