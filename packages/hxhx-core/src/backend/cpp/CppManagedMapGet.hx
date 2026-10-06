package backend.cpp;

/** Only the exact standard Map declaration selects this native operation. */
function selects(call:Null<TypedBackendInstanceCallOccurrence>):Bool {
	if (call == null)
		return false;
	final declaration = call.getDeclaration();
	return declaration.getOwner().getCanonicalName() == "haxe.ds.Map"
		&& declaration.getModulePath() == "haxe.ds.Map"
		&& declaration.getSignature().getName() == "get";
}

/** Applied result and argument facts must agree with the Map's selected key/value representation. */
function require(call:TypedBackendInstanceCallOccurrence, ?classes:CppManagedClassStorage, ?enums:CppManagedEnumDescriptors):Void {
	if (!selects(call))
		throw "managed Map.get requires its exact standard declaration";
	final declaration = call.getDeclaration();
	final signature = declaration.getSignature();
	if (declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getArgs().length != 1
		|| signature.getArgOptional().length != 1
		|| signature.getArgRest().length != 1
		|| signature.getArgOptional()[0]
		|| signature.getArgRest()[0]
		|| call.getReceiverType() == null
		|| call.getCall().arguments.length != 1
		|| call.getArgumentTypes().length != 1)
		throw "managed Map.get requires its exact ordinary instance signature";
	final storage = CppManagedMapStorage.select(call.getReceiverType(), classes, enums);
	if (call.getArgumentTypes()[0].getSemanticKey() != storage.keyType.getSemanticKey()
		|| call.getResultType().getSemanticKey() != TyType.nullable(storage.valueType).getSemanticKey())
		throw "managed Map.get requires exact applied key and nullable result types";
}

/** Evaluate receiver before key, root both through effects, and preserve missing as Null. */
function render(input:{
	call:TypedBackendInstanceCallOccurrence,
	?classes:CppManagedClassStorage,
	?enums:CppManagedEnumDescriptors,
	heap:String,
	destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	require(input.call, input.classes, input.enums);
	final call = input.call.getCall();
	final storage = CppManagedMapStorage.select(input.call.getReceiverType(), input.classes, input.enums);
	final map = input.destination + "_map_receiver";
	final key = input.destination + "_map_key";
	final reference = input.destination + "_map_storage";
	final lines = [indent + "{"];
	for (name in [map, key])
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + name + "(" + input.heap + ");");
	for (line in input.renderValue(call.receiver, map, indent + "  "))
		lines.push(line);
	for (line in input.renderValue(call.arguments[0], key, indent + "  "))
		lines.push(line);
	lines.push(indent + "  const auto " + reference + " = " + map + ".get().asManaged().as<hxhx::managed::" + storage.payload + ">();");
	final selectedKey = CppManagedMapStorage.renderKey(input.call.getReceiverType(), key + ".get()", input.classes, input.enums);
	lines.push(indent + "  " + input.destination + ".set(" + reference + "->contains(" + selectedKey + ") ? " + reference + "->readExisting(" + selectedKey
		+ ") : hxhx::managed::Value{});");
	lines.push(indent + "}");
	return lines;
}
