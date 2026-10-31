package backend.ocaml;

/**
	Array operations that this native call adapter renders through the shared
	`HxArray` runtime.

	Stage3 also emits an OCaml `Array` module from the standard `Array` class.
	A method without a Haxe body (for example `pop`) is an empty stub in that
	module. An ordinary call that reached such a stub compiled and then did
	nothing, so every bodiless standard Array method must appear here. The
	emitter rejects a bodiless Array method that is missing from this list.
 */
function supports(method:String):Bool {
	return switch method {
		case "map" | "join" | "push" | "copy" | "concat" | "slice" | "splice" | "filter" | "indexOf" | "lastIndexOf" | "sort" | "reverse" | "pop" | "shift" |
			"unshift" | "insert" | "remove" | "contains" | "toString" | "resize": true;
		case _: false;
	};
}

/**
	Retain an Array receiver when push becomes a callable value. The selected
	standard-library method has no emitted body; its implementation is the same
	mutable runtime operation used by a direct call. Capture the container now,
	then perform each insertion when the returned function is invoked.
 */
function renderMethodValue(input:{
	occurrence:TypedBackendMethodOccurrence,
	metal:Bool,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames
}):Null<String> {
	final occurrence = input.occurrence;
	final declaration = occurrence.getDeclaration();
	if (declaration.getOwner().getCanonicalName() != "Array" || declaration.getSignature().getName() != "push")
		return null;
	declaration.requireSupportedImplementation();
	final receiverType = occurrence.getReceiverType();
	final callable = occurrence.getCallableType();
	final parameters = callable.getFunctionParameters();
	if (occurrence.getUse() != ValueRead
		|| input.names == null
		|| receiverType.getNominalIdentity() == null
		|| receiverType.getNominalIdentity().getCanonicalName() != "Array"
		|| receiverType.getTypeArguments().length != 1
		|| parameters.length != 1
		|| parameters[0].isOptional
		|| parameters[0].isRest
		|| parameters[0].type.getSemanticKey() != receiverType.getTypeArguments()[0].getSemanticKey()
		|| callable.getFunctionReturn().getSemanticKey() != "primitive:Int")
		throw "OCaml Array.push value requires its exact applied receiver and callable types";
	final source = switch occurrence.getExpression() {
		case EField(receiver, _): receiver;
		case _: throw "OCaml Array.push value lost its selected receiver";
	};
	final argument = input.names.internalName("__hx_array_value");
	return Stage3OcamlMethodValue.captureReceiver({receiver: source,
		emit: input.emit,
		names: input.names,
		bind: receiver -> "fun "
			+ argument
			+ " -> "
			+ push(receiverType, parameters[0].type, input.metal ? receiver : "(Obj.magic " + receiver + ")", argument)});
}

/** Exact element and operand types select the same storage representation for calls and saved methods. */
private function push(receiverType:TyType, argumentType:TyType, receiver:String, argument:String):String {
	final stored = receiverType.getTypeArguments()[0].isDynamic() ? "(Obj.magic (" + Stage3OcamlObjects.store(argumentType, argument) + "))" : argument;
	return "HxArray.push " + receiver + " " + stored;
}

/**
	Render selected Array operations through the shared array runtime.
	The exact occurrence supplies receiver types before ordinary instance-call
	adaptation discards them. Bind receiver and argument in Haxe evaluation order;
	OCaml function application alone does not guarantee that order.
 */
function render(input:{
	occurrence:TypedBackendInstanceCallOccurrence,
	metal:Bool,
	autoMetal:Bool,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames,
	mark:String->Void
}):Null<String> {
	final occurrence = input.occurrence;
	final call = occurrence.getCall();
	if (occurrence.getDeclaration().getOwner().getCanonicalName() != "Array" || !supports(call.method))
		return null;
	// A `Null<Array<T>>` receiver, such as `map.get(key)`, uses the same array value.
	final receiverType = occurrence.getReceiverType() == null ? null : TyAliasExpansion.revealNonNullable(occurrence.getReceiverType());
	if (receiverType == null
		|| receiverType.getNominalIdentity() == null
		|| receiverType.getNominalIdentity().getCanonicalName() != "Array"
		|| receiverType.getTypeArguments().length != 1)
		throw "selected OCaml array call requires its exact Array receiver type";
	final expectedCount = switch call.method {
		case "copy" | "reverse" | "pop" | "shift" | "toString": 0;
		case "splice" | "insert": 2;
		case "slice" | "indexOf" | "lastIndexOf": call.arguments.length == 1 ? 1 : 2;
		case _: 1;
	};
	if (call.arguments.length != expectedCount || input.names == null)
		throw "selected OCaml array call requires its argument and local naming owner";
	final strings = receiverType.getTypeArguments()[0].getSemanticKey() == "primitive:String";
	final autoTyped = input.autoMetal && strings;
	final receiver = input.names.internalName("__hx_array_receiver");
	// Portable producers such as map use an erased array ABI. The checked Array
	// declaration and element type permit the native operation's typed view of
	// that same container; no slots or aliases change at this boundary.
	final runtimeReceiver = input.metal ? receiver : "(Obj.magic " + receiver + ")";
	final arguments = [
		for (index in 0...call.arguments.length)
			input.names.internalName("__hx_array_argument_" + index)
	];
	final argument = arguments.length == 0 ? "" : arguments[0];
	// Dynamic arrays store boxed values. Inserted and searched values must use
	// the same representation as push, including boxed Bool and Float values.
	final element = receiverType.getTypeArguments()[0];
	final stored = (index:Int) -> element.isDynamic() ? "(Obj.magic ("
		+ Stage3OcamlObjects.store(occurrence.getProjectedArgumentTypes()[index], arguments[index])
		+ "))" : arguments[index];
	final operation = switch (call.method) {
		case "map": if (autoTyped) input.mark("array_map_typed"); input.metal || autoTyped ? "HxBootArray.map (" + receiver + ") (" + argument + ")" : "HxBootArray.map_dyn (Obj.magic (" + receiver + ")) (Obj.repr (" + argument + "))";
		case "join":
			if (input.metal && !strings)
				throw "stage3 emitter: metal profile unsupported semantics: Array.join requires Array<String> receiver";
			if (autoTyped)
				input.mark("array_join_typed");
			if (input.metal || autoTyped) "HxBootArray.join_strict (" + receiver + ") (" + argument + ") (fun (s : string) -> s)"; else if (strings)
				"HxBootArray.join ("
				+ receiver + ") (" + argument + ") (fun (s : string) -> s)"; else "HxBootArray.join_dyn (Obj.magic (" + receiver + ")) (" + argument + ")";
		case "push":
			push(receiverType, occurrence.getProjectedArgumentTypes()[0], runtimeReceiver, argument);
		case "copy": "HxArray.copy " + runtimeReceiver;
		case "concat": "HxArray.concat " + runtimeReceiver + " " + argument;
		case "slice":
			arguments.length == 1 ? "HxArray.slice_default " + runtimeReceiver + " " + argument : "HxArray.slice "
				+ runtimeReceiver
				+ " "
				+ arguments.join(" ");
		case "splice": "HxArray.splice " + runtimeReceiver + " " + arguments.join(" ");
		case "filter": "HxArray.filter " + runtimeReceiver + " " + argument;
		case "sort":
			// The comparator keeps the element type selected by the typer, so a
			// `String` callback parameter stays `string`.
			"HxArray.sort " + runtimeReceiver + " " + argument;
		case "reverse": "HxArray.reverse " + runtimeReceiver + " ()";
		case "pop" | "shift":
			// The Haxe result is `Null<T>`: an empty array returns null. The metal
			// profile has no nullable carrier for a typed element result.
			if (input.metal)
				throw "stage3 emitter: metal profile unsupported semantics: Array." + call.method + " returns Null<T>";
			"HxArray." + call.method + " " + runtimeReceiver + " ()";
		case "unshift": "HxArray.unshift " + runtimeReceiver + " " + stored(0);
		case "insert": "HxArray.insert " + runtimeReceiver + " " + arguments[0] + " " + stored(1);
		case "remove" | "contains": "HxArray." + call.method + " " + runtimeReceiver + " " + stored(0);
		case "resize": "HxArray.resize " + runtimeReceiver + " " + argument;
		case "toString":
			// Use the element stringifier that Stage3 attaches to each array, the
			// same path as `Std.string(array)`.
			if (input.metal)
				throw "stage3 emitter: metal profile unsupported semantics: Array.toString requires a Dynamic element stringifier";
			"HxDynamic.toStdString (Obj.repr " + receiver + ")";
		case "indexOf" | "lastIndexOf":
			final searched = stored(0);
			"HxArray."
			+ call.method
			+ (arguments.length == 1 ? "_default" : "")
			+ " "
			+ runtimeReceiver
			+ " "
			+ searched
			+ (arguments.length == 1 ? "" : " " + arguments[1]);
		case _: throw "unexpected selected array operation";
	};
	final result = call.method == "map"
		&& !input.metal ? Stage3OcamlArrays.retainStringifier(occurrence.getResultType(), operation, input.names) : operation;
	final bindings = ["let " + receiver + " = (" + input.emit(call.receiver) + ") in "];
	final argumentTypes = occurrence.getArgumentTypes();
	for (index in 0...arguments.length) {
		// slice's start is a required Int; the second slot of slice/indexOf/lastIndexOf
		// is an optional int that recognizes the sentinel bits.
		final rendered = input.emit(call.arguments[index]);
		final nullableInt = index < argumentTypes.length
			&& Stage3OcamlNullablePrimitive.innerPrimitive(argumentTypes[index]) == "primitive:Int";
		final optionalSlot = index == 1 && (call.method == "slice" || call.method == "indexOf" || call.method == "lastIndexOf");
		final requiredSlot = index == 0 && call.method == "slice";
		final value = !nullableInt ? rendered : optionalSlot ? Stage3OcamlNullablePrimitive.intrinsicOptionalInt(rendered) : requiredSlot ? Stage3OcamlNullablePrimitive.unwrap("primitive:Int",
			rendered) : rendered;
		bindings.push("let " + arguments[index] + " = (" + value + ") in ");
	}
	return "(" + bindings.join("") + result + ")";
}
