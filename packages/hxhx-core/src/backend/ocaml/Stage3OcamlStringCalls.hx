package backend.ocaml;

/**
	Native adapters for the instance methods of the standard `String` class.

	`String` is an `extern` class, so none of its methods has a Haxe body.
	Stage3 still writes a `String` OCaml module for the class, and every method
	there is an empty placeholder that returns `0`. A typed `s.toUpperCase()`
	that reached that module printed `0` instead of the upper-case text. Each
	method listed here renders a call into the shared `HxString` runtime
	instead, whatever expression produced the receiver: a local, a field, an
	index, a call result, or a type check.

	The emitter rejects a typed String instance call whose method is missing
	from this list, so a new String method cannot silently reach the empty
	placeholder (see `EmitterStage.requireEmittedStdInstanceMethodBody`).
**/
function supports(method:String):Bool {
	return switch method {
		case "toUpperCase" | "toLowerCase" | "toString" | "indexOf" | "lastIndexOf" | "substr" | "substring" | "charAt" | "charCodeAt" | "split": true;
		case _: false;
	};
}

/**
	The number of source arguments each supported method accepts. A method with
	an optional `Int` bound accepts one fewer argument than its maximum.
**/
function argumentRange(method:String):{min:Int, max:Int} {
	return switch method {
		case "toUpperCase" | "toLowerCase" | "toString": {min: 0, max: 0};
		case "charAt" | "charCodeAt" | "split": {min: 1, max: 1};
		case _: {min: 1, max: 2};
	};
}

/**
	Render the selected String declaration before ordinary instance-call adaptation.
	The typed occurrence supplies the receiver and operands; a matching method name
	alone cannot select this runtime. Bind supplied values once in Haxe source order.
	The existing runtime accepts the canonical null sentinel for an omitted bound,
	so zero remains an explicit bound and no receiver is evaluated again for defaults.

	Each rendered call matches the `HxString` runtime signature:
	- `toUpperCase`, `toLowerCase`, `toString`: `string -> unit -> string`;
	- `charAt`: `string -> int -> string`;
	- `charCodeAt`: `string -> int -> Obj.t` (an Int or the null sentinel);
	- `split`: `string -> string -> string HxArray.t`;
	- `indexOf`, `lastIndexOf`: `string -> string -> int -> int`;
	- `substr`, `substring`: `string -> int -> int -> string`.
 */
function render(input:{
	occurrence:TypedBackendInstanceCallOccurrence,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames
}):Null<String> {
	final occurrence = input.occurrence;
	final call = occurrence.getCall();
	if (occurrence.getDeclaration().getOwner().getCanonicalName() != "String" || !supports(call.method))
		return null;
	final receiverType = occurrence.getReceiverType();
	if (receiverType == null || receiverType.unwrapNull().getSemanticKey() != "primitive:String")
		throw "selected OCaml string call requires its exact String receiver type";
	final range = argumentRange(call.method);
	if (call.arguments.length < range.min || call.arguments.length > range.max)
		throw "selected OCaml string call " + call.method + " requires " + range.min + " to " + range.max + " arguments";
	if (input.names == null)
		throw "selected OCaml string call requires its local naming owner";
	final characterRead = call.method == "charAt" || call.method == "charCodeAt";
	final receiver = input.names.internalName("__hx_string_receiver");
	final arguments = [
		for (index in 0...call.arguments.length)
			input.names.internalName("__hx_string_argument_" + index)
	];
	final bindings = ["let " + receiver + " = (" + input.emit(call.receiver) + ") in "];
	final argumentTypes = occurrence.getArgumentTypes();
	for (index in 0...arguments.length) {
		// charAt and charCodeAt take a required index; the other slots are optional
		// ints that recognize the sentinel bits, so a nullable Int carrier passes through.
		final rendered = input.emit(call.arguments[index]);
		final nullableInt = index < argumentTypes.length
			&& Stage3OcamlNullablePrimitive.innerPrimitive(argumentTypes[index]) == "primitive:Int";
		final value = !nullableInt ? rendered : characterRead ? Stage3OcamlNullablePrimitive.unwrap("primitive:Int",
			rendered) : Stage3OcamlNullablePrimitive.intrinsicOptionalInt(rendered);
		bindings.push("let " + arguments[index] + " = (" + value + ") in ");
	}
	// The case-conversion and identity methods take a unit argument after the receiver.
	if (range.max == 0)
		return "(" + bindings.join("") + "HxString." + call.method + " " + receiver + " ())";
	if (call.method == "charCodeAt") {
		// The runtime produces an Int or the canonical null sentinel. Restore the
		// Stage3 nullable value view without inspecting bits or unwrapping null;
		// an authored null test must still run before any integer operation.
		return "(" + bindings.join("") + "Obj.magic (HxString.charCodeAt " + receiver + " " + arguments[0] + "))";
	}
	// split returns the shared `string HxArray.t` Array<String> representation;
	// charAt returns an ordinary String, including "" outside the bounds.
	if (range.max == 1)
		return "(" + bindings.join("") + "HxString." + call.method + " " + receiver + " " + arguments[0] + ")";
	// HxString's optional Int ABI recognizes this sentinel before integer use.
	// This is a representation boundary, not an unchecked source-type conversion.
	if (arguments.length == 1)
		arguments.push("(Obj.magic HxRuntime.hx_null)");
	return "(" + bindings.join("") + "HxString." + call.method + " " + receiver + " " + arguments.join(" ") + ")";
}
