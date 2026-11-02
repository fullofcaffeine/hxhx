package backend.ocaml;

/**
	Native adapters for `EReg` construction and instance calls in Stage3 OCaml output.

	Why
	- On the OCaml target `EReg` is an `extern` class. It has no Haxe body; its
	  OCaml implementation is the shared runtime file `EReg.ml`, which Stage3
	  copies next to the generated modules. Stage3 writes no `EReg` module of
	  its own.
	- Stage3 had no construction route for that runtime module. A regex literal
	  such as `~/b+/g` is parsed as `new EReg("b+", "g")`, so both forms produced
	  the placeholder `(Obj.magic 0)`. When the regex was a call receiver or
	  argument, the whole statement became a placeholder and was dropped. The
	  build succeeded, and the executable crashed on the first `match`.
	- Instance calls reached the runtime only through the generic module call,
	  which does not know that the runtime's zero-argument methods
	  (`matchedLeft`, `matchedRight`, `matchedPos`) take a trailing unit. Those
	  calls returned an unapplied function instead of the result.

	What
	- `renderConstruction` calls `EReg.create pattern flags`.
	- `render` calls the runtime export for each instance method, with the
	  receiver first. Haxe `match` is exported as `hx_match`, because `match`
	  is an OCaml keyword. Operands are bound once, in Haxe source order.

	Selection uses the typed declaration's canonical owner `EReg`, never the
	method name alone, so a user class with an `EReg`-like method is unaffected.
	The runtime signatures these calls rely on are listed on `render`.
**/
private function ownsName(canonicalName:String):Bool {
	return canonicalName == "EReg";
}

/** Whether `constructed` is the standard `EReg` class. */
function ownsConstruction(constructed:TyType):Bool {
	final identity = constructed == null ? null : constructed.getNominalIdentity();
	return identity != null && ownsName(identity.getCanonicalName());
}

/**
	Construct a regex with `EReg.create`. `arguments` are the rendered pattern
	and flags strings. `runtimeModules` names the runtime modules copied into
	this build; a build without `EReg.ml` is an emit-time error, not a placeholder.
**/
function renderConstruction(input:{
	arguments:Array<String>,
	runtimeModules:Map<String, Bool>,
	names:Null<Stage3OcamlLocalNames>
}):String {
	if (input.arguments.length != 2)
		throw "stage3 emitter: new EReg(...) needs a pattern and flags, got " + input.arguments.length + " arguments";
	if (input.runtimeModules == null || !input.runtimeModules.exists("EReg"))
		throw "stage3 emitter: new EReg(...) needs the OCaml runtime module EReg, which this build does not include";
	return Stage3OcamlCallOrder.render({callee: "EReg.create", arguments: input.arguments, names: input.names});
}

/**
	The `EReg.ml` export and the accepted source argument count for one EReg
	instance method. A method without an adapter is an emit-time error.
**/
function instanceMethod(method:String):{export:String, min:Int, max:Int} {
	return switch method {
		case "match": {export: "hx_match", min: 1, max: 1};
		case "matched": {export: "matched", min: 1, max: 1};
		case "matchedLeft" | "matchedRight" | "matchedPos": {export: method, min: 0, max: 0};
		case "matchSub": {export: "matchSub", min: 2, max: 3};
		case "split": {export: "split", min: 1, max: 1};
		case "replace" | "map": {export: method, min: 2, max: 2};
		case _: throw "stage3 emitter: EReg." + method + " has no native adapter in Stage3OcamlERegCalls";
	};
}

/**
	Render one typed `EReg` instance call, or return `null` when the declaration
	is not the standard `EReg` class. An `EReg` method without an adapter is an
	emit-time error.

	Each rendered call matches the `EReg.ml` runtime signature:
	- `hx_match`: `t -> string -> bool`;
	- `matched`: `t -> int -> string`;
	- `matchedLeft`, `matchedRight`: `t -> unit -> string`;
	- `matchedPos`: `t -> unit -> Obj.t` (an object with `pos` and `len`);
	- `matchSub`: `t -> string -> int -> int -> bool`, where the null sentinel
	  for `len` means the rest of the string;
	- `split`: `t -> string -> string HxArray.t`;
	- `replace`: `t -> string -> string -> string`;
	- `map`: `t -> string -> (t -> string) -> string`.
**/
function render(input:{
	occurrence:TypedBackendInstanceCallOccurrence,
	emit:HxExpr->String,
	names:Null<Stage3OcamlLocalNames>
}):Null<String> {
	final occurrence = input.occurrence;
	if (!ownsName(occurrence.getDeclaration().getOwner().getCanonicalName()))
		return null;
	final call = occurrence.getCall();
	final range = instanceMethod(call.method);
	if (call.arguments.length < range.min || call.arguments.length > range.max)
		throw "stage3 emitter: EReg."
			+ call.method
			+ " takes "
			+ range.min
			+ " to "
			+ range.max
			+ " arguments, got "
			+ call.arguments.length;
	final arguments = [input.emit(call.receiver)].concat([for (argument in call.arguments) input.emit(argument)]);
	// The runtime's zero-argument methods take a unit after the receiver.
	if (range.max == 0)
		arguments.push("()");
	// The runtime reads this sentinel as an omitted `len`, like Haxe's default -1.
	if (call.method == "matchSub" && call.arguments.length == 2)
		arguments.push("(Obj.magic HxRuntime.hx_null)");
	return Stage3OcamlCallOrder.render({callee: "EReg." + range.export, arguments: arguments, names: input.names});
}
