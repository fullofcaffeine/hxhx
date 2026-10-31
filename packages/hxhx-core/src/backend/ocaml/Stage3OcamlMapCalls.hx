package backend.ocaml;

/**
	The key family of one native `HxMap` table: String keys, Int keys, or
	objects compared by identity.
**/
enum Stage3OcamlMapKeys {
	StringKeys;
	IntKeys;
	ObjectKeys;
}

/** The runtime table, key type, and value type selected for one typed Map call or allocation. */
typedef Stage3OcamlMapStorage = {
	final keys:Stage3OcamlMapKeys;
	final keyType:TyType;
	final valueType:TyType;
}

/**
	Native adapters for the standard Haxe maps in Stage3 OCaml output.

	Why
	- `haxe.ds.StringMap`, `IntMap`, and `ObjectMap` are `extern` classes, so
	  none of their methods has a Haxe body. Stage3 still writes an OCaml module
	  for each one, and every method there is an empty placeholder. Before this
	  adapter, `new StringMap()` produced the placeholder value `0`, `s.set("a", 1)`
	  did nothing, and `s.get("a")` returned `0` with exit code 0.
	- The `Map<K, V>` abstract forwards each method to its backing value through
	  the `IMap` interface. Expanding those inline bodies produced `IMap` calls,
	  which Stage3 also bound to empty placeholders; iterating `m.keys()` then
	  crashed with SIGBUS.

	What
	- `new StringMap()`, `new IntMap()`, and `new ObjectMap()` allocate the
	  shared `HxMap` runtime table for their key family.
	- Every instance method of those three classes renders the matching `HxMap`
	  operation: set, get (null for a missing key), exists, remove, keys,
	  iterator, keyValueIterator, copy, toString, and clear.
	- Calls to the same methods of `Map<K, V>`, plus the `arrayWrite` method that
	  `map[key] = value` selects, stay calls until emission (see
	  `Stage3OcamlNativeCallPolicy`). They render here for `String` and `Int`
	  keys, the same tables that `new Map()` allocates through `toStringMap` and
	  `toIntMap`. Map literals and `map[key]` reads use these same methods.

	How
	- The typed occurrence supplies the exact declaration and applied receiver
	  type. A method name alone never selects this runtime.
	- The receiver is bound once, then the arguments in Haxe source order.
	- Stage3 calls `hasNext` and `next` on a structural `Iterator<T>` by reading
	  fields of an anonymous object. The iterator methods therefore return an
	  anonymous object with those two closures over a runtime array snapshot,
	  built with the same `HxAnon` primitives as an object literal.
	  `keyValueIterator` yields `{key, value}` objects whose fields use the same
	  storage as other object fields, so a Bool value keeps its boxed form.

	Limits
	- `Map<K, V>` with any other key type (an enum, a class, an anonymous
	  structure, or a type parameter) is an emit-time error, not a placeholder.
	  Upstream selects `EnumValueMap` or `ObjectMap` for those keys.
	- Iteration and `toString` follow the runtime table's order. Upstream Haxe
	  does not define a Map iteration order either.
	- `Std.string(map)` and string concatenation do not use these adapters.
**/
function ownerKeys(owner:String):Null<Stage3OcamlMapKeys> {
	return switch owner {
		case "haxe.ds.StringMap": StringKeys;
		case "haxe.ds.IntMap": IntKeys;
		case "haxe.ds.ObjectMap": ObjectKeys;
		case _: null;
	};
}

/** Whether an instance call on this owner must be rendered here or rejected. */
function ownsInstanceCall(owner:String):Bool
	return owner == "haxe.ds.Map" || ownerKeys(owner) != null;

/** The instance methods of the extern map classes; each one has an adapter below. */
function supports(method:String):Bool
	return Stage3OcamlNativeCallPolicy.supportsMapMethod(method);

/** Whether shared preparation keeps this `Map<K, V>` method as a call for this adapter. */
function retainsAbstractDeclaration(declaration:TyDeclarationInfo):Bool
	return Stage3OcamlNativeCallPolicy.retain(declaration);

/** Select the table from an applied extern map class or a `Map<K, V>` with String or Int keys. */
function storage(owner:String, receiverType:Null<TyType>, method:String):Stage3OcamlMapStorage {
	if (receiverType == null)
		throw "selected OCaml map call " + owner + "." + method + " requires its exact receiver type";
	final applied = TyAliasExpansion.revealNonNullable(receiverType);
	final identity = applied.getNominalIdentity();
	final arguments = applied.getTypeArguments();
	if (identity == null || identity.getCanonicalName() != owner || applied.hasUnknownComponent())
		throw "selected OCaml map call " + owner + "." + method + " requires its exact applied receiver";
	final direct = ownerKeys(owner);
	if (direct == StringKeys || direct == IntKeys) {
		if (arguments.length != 1)
			throw "selected OCaml map call " + owner + "." + method + " requires one value type";
		return {keys: direct, keyType: TyType.fromHintText(direct == StringKeys ? "String" : "Int"), valueType: arguments[0]};
	}
	if (arguments.length != 2)
		throw "selected OCaml map call " + owner + "." + method + " requires key and value types";
	if (direct == ObjectKeys)
		return {keys: ObjectKeys, keyType: arguments[0], valueType: arguments[1]};
	final keys = switch arguments[0].getSemanticKey() {
		case "primitive:String": StringKeys;
		case "primitive:Int": IntKeys;
		case _: throw "stage3 emitter: Map<"
				+ arguments[0].getCanonicalDisplay() + ", " + arguments[1].getCanonicalDisplay()
					+ ">."
					+ method
					+ " has no native map storage yet; only String and Int keys are supported (haxe_ocaml-njq5n)";
	};
	return {keys: keys, keyType: arguments[0], valueType: arguments[1]};
}

private function suffix(keys:Stage3OcamlMapKeys):String {
	return switch keys {
		case StringKeys: "string";
		case IntKeys: "int";
		case ObjectKeys: "object";
	};
}

/** Allocate the runtime table for `new StringMap()`, `new IntMap()`, or `new ObjectMap()`. */
function renderConstruction(constructed:TyType, argumentCount:Int):Null<String> {
	final identity = constructed == null ? null : constructed.getNominalIdentity();
	final keys = identity == null ? null : ownerKeys(identity.getCanonicalName());
	if (keys == null)
		return null;
	if (argumentCount != 0)
		throw "OCaml " + identity.getCanonicalName() + " construction takes no arguments";
	return "(HxMap.create_" + suffix(keys) + " ())";
}

/**
	Build a structural iterator over a runtime array snapshot.
	`item` converts one array element to the value that `next()` returns.
**/
private function iterator(items:String, item:String->String, names:Stage3OcamlLocalNames):String {
	final snapshot = names.internalName("__hx_map_items");
	final cursor = names.internalName("__hx_map_cursor");
	final object = names.internalName("__hx_map_iterator");
	final element = names.internalName("__hx_map_item");
	return "(let " + snapshot + " = (" + items + ") in let " + cursor + " = ref 0 in let " + object + " = HxAnon.create () in " + "HxAnon.set " + object
		+ " \"hasNext\" (Obj.repr (fun () -> !" + cursor + " < HxArray.length " + snapshot + ")); " + "HxAnon.set " + object
		+ " \"next\" (Obj.repr (fun () -> let " + element + " = HxArray.get " + snapshot + " !" + cursor + " in " + cursor + " := !" + cursor + " + 1; "
		+ item(element) + ")); " + object + ")";
}

/** Text for one key or value, using the same rendering as `Std.string`. */
private function text(type:TyType, value:String):String
	return "HxDynamic.toStdString (" + Stage3OcamlObjects.store(type, value) + ")";

/** One `{key, value}` object for `keyValueIterator`, stored like any other object field. */
private function pairObject(item:String, selected:Stage3OcamlMapStorage, names:Stage3OcamlLocalNames, quote:String->String):String {
	final key = names.internalName("__hx_map_key");
	final value = names.internalName("__hx_map_value");
	final pair = names.internalName("__hx_map_pair");
	return ["let (" + key + ", " + value + ") = " + item + " in ",
		"let " + pair + " = HxAnon.create () in ",
		"HxAnon.set "
		+ pair
		+ " "
		+ quote("key")
		+ " ("
		+ Stage3OcamlObjects.store(selected.keyType, key)
		+ "); ",
		"HxAnon.set "
		+ pair
		+ " "
		+ quote("value")
		+ " ("
		+ Stage3OcamlObjects.store(selected.valueType, value)
		+ "); ",
		pair
	].join("");
}

/**
	Render a typed map instance call, or return null when the method has no adapter.
	The caller rejects a null result for these owners instead of calling a placeholder.
**/
function render(input:{
	occurrence:TypedBackendInstanceCallOccurrence,
	emit:HxExpr->String,
	names:Stage3OcamlLocalNames,
	quote:String->String
}):Null<String> {
	final occurrence = input.occurrence;
	final call = occurrence.getCall();
	final owner = occurrence.getDeclaration().getOwner().getCanonicalName();
	if (!ownsInstanceCall(owner))
		return null;
	final method = call.method;
	if (owner == "haxe.ds.Map" ? !retainsAbstractDeclaration(occurrence.getDeclaration()) : !supports(method))
		return null;
	final selected = storage(owner, occurrence.getReceiverType(), method);
	final expectedCount = switch method {
		case "set" | "arrayWrite": 2;
		case "get" | "exists" | "remove": 1;
		case _: 0;
	};
	if (call.arguments.length != expectedCount)
		throw "selected OCaml map call " + owner + "." + method + " requires " + expectedCount + " arguments";
	if (input.names == null)
		throw "selected OCaml map call requires its local naming owner";
	final receiver = input.names.internalName("__hx_map_receiver");
	final arguments = [
		for (index in 0...call.arguments.length)
			input.names.internalName("__hx_map_argument_" + index)
	];
	final bindings = ["let " + receiver + " = (" + input.emit(call.receiver) + ") in "];
	for (index in 0...arguments.length)
		bindings.push("let " + arguments[index] + " = (" + input.emit(call.arguments[index]) + ") in ");
	final table = "(Obj.magic " + receiver + ")";
	final operation = (name:String) -> "HxMap." + name + "_" + suffix(selected.keys) + " " + table;
	// A Dynamic value keeps the carrier that every other Dynamic slot stores.
	final stored = () -> selected.valueType.isDynamic() ? "(Obj.magic ("
		+ Stage3OcamlObjects.store(occurrence.getProjectedArgumentTypes()[1], arguments[1])
		+ "))" : arguments[1];
	final rendered = switch method {
		case "set": operation("set") + " " + arguments[0] + " " + stored();
		case "arrayWrite": "(" + operation("set") + " " + arguments[0] + " " + stored() + "; " + arguments[1] + ")";
		case "get" | "exists" | "remove": operation(method) + " " + arguments[0];
		case "clear" | "copy": operation(method);
		case "keys": iterator(operation("keys"), item -> item, input.names);
		case "iterator": iterator(operation("values"), item -> item, input.names);
		case "keyValueIterator":
			iterator(operation("pairs"), item -> pairObject(item, selected, input.names, input.quote), input.names);
		case "toString":
			// Upstream prints `[key => value, ...]` with Std.string text for each side.
			final key = input.names.internalName("__hx_map_key");
			final value = input.names.internalName("__hx_map_value");
			"\"[\" ^ HxArray.join ("
			+ operation("pairs")
			+ ") \", \" (fun ("
			+ key
			+ ", "
			+ value
			+ ") -> "
			+ text(selected.keyType, key)
			+ " ^ \" => \" ^ "
			+ text(selected.valueType, value)
			+ ") ^ \"]\"";
		case _: throw "unexpected selected map operation " + method;
	};
	return "(" + bindings.join("") + rendered + ")";
}

/**
	Allocate the table for a `Map<K, V>` literal and insert each arrow entry in
	source order. Each key is evaluated before its value, and an entry is
	inserted before the next entry is evaluated, so a later duplicate key wins.
**/
function renderLiteral(aggregate:TypedBackendAggregateOccurrence, emit:HxExpr->String, names:Stage3OcamlLocalNames):String {
	if (names == null)
		throw "OCaml map literal requires its local naming owner";
	final selected = storage("haxe.ds.Map", aggregate.getType(), "literal");
	final table = names.internalName("__hx_map_literal");
	final out = ["(let " + table + " = HxMap.create_" + suffix(selected.keys) + " () in "];
	final entries = aggregate.getMapEntries();
	for (index in 0...entries.length) {
		final entry = entries[index];
		final key = names.internalName("__hx_map_key_" + index);
		final value = names.internalName("__hx_map_value_" + index);
		final stored = selected.valueType.isDynamic() ? "(Obj.magic (" + Stage3OcamlObjects.store(entry.valueType, value) + "))" : value;
		out.push("let " + key + " = (" + emit(entry.key) + ") in let " + value + " = (" + emit(entry.value) + ") in HxMap.set_" + suffix(selected.keys)
			+ " " + table + " " + key + " " + stored + "; ");
	}
	out.push(table + ")");
	return out.join("");
}
