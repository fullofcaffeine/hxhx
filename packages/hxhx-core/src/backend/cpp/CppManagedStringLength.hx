package backend.cpp;

/** Only the standard String field uses native text storage; authored length fields keep their class layout. */
function selects(occurrence:Null<TypedBackendFieldOccurrence>):Bool {
	return occurrence != null
		&& occurrence.getField().getModulePath() == "String"
		&& occurrence.getField().getCanonicalKey() == "String#instance#length";
}

/** The caller checks exact executable ownership before this read-only field contract. */
function require(occurrence:TypedBackendFieldOccurrence):Void {
	if (!selects(occurrence))
		throw "managed String.length requires its exact standard field";
	final field = occurrence.getField();
	if (field.getIsStatic()
		|| field.getType().getSemanticKey() != "primitive:Int"
		|| occurrence.getType().getSemanticKey() != "primitive:Int"
		|| occurrence.getReceiver() != ValueReceiver
		|| field.getPropertyGet() != "default"
		|| field.getPropertySet() != "null")
		throw "managed String.length requires its exact read-only Int field contract";
}

/** Evaluate the receiver once and publish its UTF-16 length only after the native read succeeds. */
function read(input:{
	occurrence:TypedBackendFieldOccurrence,
	heap:String,
	destination:String,
	renderReceiver:(TypedBackendFieldOccurrence, String, String) -> Array<String>
}, indent:String):Array<String> {
	require(input.occurrence);
	final receiver = input.destination + "_string_length_receiver";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + receiver + "(" + input.heap + ");"
	];
	for (line in input.renderReceiver(input.occurrence, receiver, indent + "  "))
		lines.push(line);
	lines.push(indent + "  " + input.destination + ".set(hxhx::managed::stringLength(" + receiver + ".get()));");
	lines.push(indent + "}");
	return lines;
}
