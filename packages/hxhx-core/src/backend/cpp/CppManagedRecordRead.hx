package backend.cpp;

/** Select required anonymous fields from the receiver's semantic structure, never nominal-name guesses. */
function fieldType(receiver:TyType, name:String):TyType {
	if (!receiver.isAnonymous())
		throw "managed record read requires an exact anonymous receiver";
	final index = receiver.getAnonymousFieldNames().indexOf(name);
	if (index < 0)
		throw "managed record read lacks its exact structural field";
	return receiver.getAnonymousFieldTypes()[index];
}

/** Root the receiver before reading and copy the selected value into the caller's result root. */
function render(input:{
	receiver:HxExpr,
	type:TyType,
	name:String,
	heap:String,
	destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	fieldType(input.type, input.name);
	final root = input.destination + "_receiver";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
	];
	for (line in input.renderValue(input.receiver, root, indent + "  "))
		lines.push(line);
	lines.push(indent
		+ "  if ("
		+ root
		+ ".get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument(\"field read has no record\");");
	lines.push(indent
		+ "  "
		+ input.destination
		+ ".set("
		+ root
		+ ".get().asManaged().as<hxhx::managed::RecordPayload>()->read("
		+ CppManagedText.literal(input.name)
		+ "));");
	lines.push(indent + "}");
	return lines;
}
