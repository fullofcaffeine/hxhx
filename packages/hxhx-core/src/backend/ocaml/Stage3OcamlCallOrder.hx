package backend.ocaml;

/**
	Apply an already-selected function after evaluating its arguments in Haxe order.
	OCaml application can evaluate arguments right to left. Nested bindings preserve
	callee capture and each argument's effects without changing their checked carriers.
	The caller still owns declaration selection, argument alignment, and conversions.
 */
function render(input:{callee:String, arguments:Array<String>, names:Stage3OcamlLocalNames}):String {
	if (input.names == null || input.arguments.length == 0)
		throw "ordered OCaml application requires a local naming owner and arguments";
	final callee = input.names.internalName("__hx_call_function");
	final arguments = [
		for (index in 0...input.arguments.length)
			input.names.internalName("__hx_call_argument_" + index)
	];
	var body = callee + " " + arguments.join(" ");
	var index = input.arguments.length;
	while (index-- > 0)
		body = "let " + arguments[index] + " = (" + input.arguments[index] + ") in " + body;
	return "(let " + callee + " = (" + input.callee + ") in " + body + ")";
}
