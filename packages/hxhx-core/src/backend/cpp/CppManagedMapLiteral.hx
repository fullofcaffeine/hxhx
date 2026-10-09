package backend.cpp;

/**
	Construct an arrow Map with rooted key/value evaluation in authored order.
	Exact aggregate facts supply operand types; rendered expressions never infer
	them. The result is published only after all entries complete. Repeated keys
	use the same insertion primitive as comprehensions and replace prior values.
 */
function render(input:CppManagedAggregate.CppManagedAggregateInput, indent:String):Array<String> {
	final storage = CppManagedMapStorage.select(input.occurrence.getType(), input.classes, input.enums);
	final entries = input.occurrence.getMapEntries();
	if (entries.length != input.occurrence.getChildren().length)
		throw "managed Map literal requires every typed arrow entry";
	for (entry in entries)
		if (entry.keyType.getSemanticKey() != storage.keyType.getSemanticKey()
			|| (!CppManagedValueTransfer.accepts(storage.valueType, entry.valueType, input.casts)
				&& !CppManagedNumericErasure.selects(storage.valueType, entry.valueType, input.casts)))
			throw "managed Map literal entry requires an explicit typed conversion";
	final parent = input.destination + "_map";
	final key = input.destination + "_key";
	final value = input.destination + "_value";
	final lines = [indent + "{",
		indent
		+ "  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::"
		+ storage.payload
		+ ">> "
		+ parent
		+ "("
		+ input.heap
		+ ");",
		indent + "  " + input.heap + ".allocateInto(" + parent + ");"
	];
	if (entries.length > 0)
		for (name in [key, value])
			lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + name + "(" + input.heap + ");");
	for (entry in entries) {
		for (line in input.renderValue(entry.key, key, indent + "  "))
			lines.push(line);
		for (line in input.renderValue(entry.value, value, indent + "  "))
			lines.push(line);
		for (line in CppManagedValueTransfer.convertRoot(storage.valueType, entry.valueType, value, indent + "  ", input.casts))
			lines.push(line);
		lines.push(indent
			+ "  "
			+ parent
			+ ".get()->insert("
			+ CppManagedMapStorage.renderKey(input.occurrence.getType(), key + ".get()", input.classes, input.enums)
			+ ", "
			+ value
			+ ".get());");
		lines.push(indent + "  " + key + ".set({});");
		lines.push(indent + "  " + value + ".set({});");
	}
	lines.push(indent + "  " + input.destination + ".set(hxhx::managed::Value::managed(" + parent + ".get()));");
	lines.push(indent + "}");
	return lines;
}
