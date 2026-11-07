package backend.ocaml;

/**
	Fill the omitted trailing optional arguments of a call through a local function.

	Why
	- A local function with `?x:Int` or `x:Int = 3` keeps every parameter in its
	  native OCaml signature. A Haxe call may leave such trailing arguments out,
	  but a native call must supply every parameter.

	What
	- Returns one null sentinel per omitted trailing parameter. The function entry
	  reads the sentinel as "absent" and applies the default, exactly as for a
	  call that passes `null`.

	How
	- The typed call gives the callee's checked function type. Each supplied
	  argument must align with the parameter at its own position. A call that
	  skipped an optional parameter by type, or that omits a required parameter,
	  stops emission instead of shifting arguments.
 */
function omitted(call:Null<TypedExpr>, supplied:Array<Null<TypedBackendCallArgument>>, slots:SentinelSlots):Array<String> {
	// Supplied arguments are only inspected when some parameter is omitted.
	if (call == null || call.getTag() != Call || call.getExpressions().length == 0)
		throw "OCaml local function call requires its exact typed call";
	final calleeType = TyAliasExpansion.reveal(call.getExpressions()[0].getType());
	if (!calleeType.isFunction())
		throw "OCaml local function call requires a function-typed callee";
	final parameters = calleeType.getFunctionParameters();
	if (supplied.length == parameters.length)
		return [];
	if (supplied.length > parameters.length)
		throw "OCaml local function call supplies more arguments than its parameters";
	for (index in 0...supplied.length) {
		final argument = supplied[index];
		if (argument == null || argument.expectedType == null)
			throw "OCaml local function call requires typed arguments when it omits parameters";
		if (argument.expectedType.getSemanticKey() != parameters[index].type.getSemanticKey()
			|| argument.expectedIsOptional != parameters[index].isOptional)
			throw "OCaml local function call that skips an optional parameter is not supported";
	}
	final sentinels = new Array<String>();
	for (index in supplied.length...parameters.length) {
		final parameter = parameters[index];
		if (parameter.isRest || !parameter.isOptional)
			throw "OCaml local function call omits a required parameter";
		requireSentinelSlot(parameter, slots);
		sentinels.push("(Obj.magic HxRuntime.hx_null)");
	}
	return sentinels;
}

/** Request facts that say which native slots are pointers. */
typedef SentinelSlots = {
	/** Answers whether a type is an enum value stored as an `Obj.t` box. */
	final isEnumBox:TyType->Bool;

	/** Answers a carrier for an Array, program class instance, anonymous structure or function value, else null. */
	final referenceCarrier:TyType->Null<String>;
}

/**
	True when the native slot of an optional or defaulted parameter can hold the
	null sentinel. Int and Float use the nullable carrier. String, Dynamic, enum
	boxes and references are pointers, so null is a valid value there. A Bool is
	an unboxed OCaml `bool` and an abstract uses its backing value, so neither
	can tell null apart from a real value.
 */
function acceptsSentinel(parameter:TyFunctionParameter, slots:SentinelSlots):Bool {
	if (Stage3OcamlNullablePrimitive.destinationCarrier(parameter.type, parameter.isOptional) != null)
		return true;
	final value = TyAliasExpansion.revealNonNullable(TyAliasExpansion.reveal(parameter.type));
	if (value.isDynamic() || value.getSemanticKey() == "primitive:String")
		return true;
	if (slots == null)
		return false;
	return (slots.isEnumBox != null && slots.isEnumBox(value))
		|| (slots.referenceCarrier != null && slots.referenceCarrier(value) != null);
}

/** Stop emission for an optional or defaulted parameter whose slot cannot hold null. */
function requireSentinelSlot(parameter:TyFunctionParameter, slots:SentinelSlots):Void {
	if (!acceptsSentinel(parameter, slots))
		throw "OCaml local function optional parameter has no native null slot: " + parameter.type.getDisplay();
}
