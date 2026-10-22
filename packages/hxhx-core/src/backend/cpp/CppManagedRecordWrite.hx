package backend.cpp;

/** Select one writable structural member from the receiver's exact applied type. */
function field(receiver:TyType, name:String):TyAnonymousField {
	final type = receiver.unwrapNull();
	CppManagedClosureAbi.assertComplete(type);
	if (!type.isAnonymous())
		throw "managed record assignment requires an exact anonymous receiver";
	for (field in type.getAnonymousFields())
		if (field.name == name) {
			if (field.visibility != Public)
				throw "managed record assignment requires a public field";
			switch field.kind {
				case Variable(false, _, setter) if (setter == "" || setter == "default"):
					return field;
				case _:
					throw "managed record assignment requires an ordinary mutable field";
			}
		}
	throw "managed record assignment lacks its exact structural field";
}

/**
	Root the selected receiver before RHS effects, then publish the converted value.
	Pinned hxcpp observations require receiver-before-value order even when the
	assignment result is discarded. A failed operand cannot change the old field.
	No native map entry address survives a source call. Optional absence permits
	creating the selected field; a required field must already exist in storage.
 */
function render(input:{
	receiver:HxExpr,
	receiverType:TyType,
	name:String,
	value:HxExpr,
	valueType:TyType,
	?casts:CppManagedCastPlan,
	heap:String,
	prefix:String,
	destination:Null<String>,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final selected = field(input.receiverType, input.name);
	if (!CppManagedValueTransfer.supports(selected.type, input.valueType, input.casts))
		throw "managed record assignment requires an explicit typed conversion";
	final receiver = input.prefix + "receiver";
	final value = input.prefix + "value";
	final payload = input.prefix + "payload";
	final name = CppManagedText.literal(selected.name);
	final lines = [indent + "{",
		indent
		+ "  hxhx::managed::Root<hxhx::managed::Value> "
		+ receiver
		+ "("
		+ input.heap
		+ "), "
		+ value
		+ "("
		+ input.heap
		+ ");"];
	for (line in input.renderValue(input.receiver, receiver, indent + "  "))
		lines.push(line);
	for (line in input.renderValue(input.value, value, indent + "  "))
		lines.push(line);
	for (line in CppManagedValueTransfer.convertRoot(selected.type, input.valueType, value, indent + "  ", input.casts))
		lines.push(line);
	lines.push(indent
		+ "  if ("
		+ receiver
		+ '.get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument("field assignment has no record");');
	lines.push(indent + "  const auto " + payload + " = " + receiver + ".get().asManaged().as<hxhx::managed::RecordPayload>();");
	if (selected.isOptional) {
		lines.push(indent + "  if (!" + payload + "->contains(" + name + ")) " + payload + "->define(" + name + ", " + value + ".get());");
		lines.push(indent + "  else " + payload + "->write(" + name + ", " + value + ".get());");
	} else
		lines.push(indent + "  " + payload + "->write(" + name + ", " + value + ".get());");
	if (input.destination != null)
		lines.push(indent + "  " + input.destination + ".set(" + value + ".get());");
	lines.push(indent + "}");
	return lines;
}
