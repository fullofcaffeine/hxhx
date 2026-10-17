package backend.vm;

/**
	Bind a runtime field to its receiver before invoking the resulting function.

	Neko native methods can inspect their receiver, including the VM loader's
	loadprim method. The native closure primitive preserves that receiver without
	introducing a Haxe function body or duplicating evaluation of the receiver.
	A method value evaluates its receiver and field when the value is extracted.
	https://nekovm.org/specs/functions/ documents this receiver-binding primitive.
**/
function bind(program:NekoTypedProgramProjection, receiver:String, field:String):String {
	final object = program.runtimeHelperName("__hxhx_call_receiver");
	return "({ var "
		+ object
		+ " = "
		+ receiver
		+ "; $closure(__hxhx_field("
		+ object
		+ ", "
		+ haxe.Json.stringify(field)
		+ "), "
		+ object
		+ "); })";
}

/**
	Evaluate the receiver before arguments, but read its field after arguments.
	Neko evaluates value-call arguments before the callee expression. Keeping the
	receiver in an outer block preserves Haxe's field-call order, including argument
	effects before a null receiver's field lookup throws.
**/
function render(program:NekoTypedProgramProjection, receiver:String, field:String, arguments:Array<String>):String {
	final object = program.runtimeHelperName("__hxhx_call_receiver");
	return "({ var " + object + " = " + receiver + "; $closure(__hxhx_field(" + object + ", " + haxe.Json.stringify(field) + "), " + object + ")("
		+ arguments.join(", ") + "); })";
}
