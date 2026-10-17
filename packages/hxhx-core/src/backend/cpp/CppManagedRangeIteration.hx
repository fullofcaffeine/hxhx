package backend.cpp;

/**
	Evaluate both integer bounds once, from left to right. The upper bound remains
	exclusive. Each iteration publishes a fresh binding cell when a closure captures
	it. The cursor cannot overflow: it increments only while below an Int upper bound.
 */
function render(input:{
	access:CppManagedLocalAccess,
	binding:HxForBinding,
	iterable:HxExpr,
	start:HxExpr,
	end:HxExpr,
	heap:String,
	prefix:String,
	renderValue:(HxExpr, String, String) -> Array<String>,
	renderBody:String->Array<String>
}, indent:String):Array<String> {
	input.access.requireLoop(input.binding, input.iterable);
	final name = switch input.binding {
		case Value(name): name;
		case _: throw "managed integer range cannot have a key/value binding";
	};
	final binding = input.access.binding(name);
	if (binding.getType().getSemanticKey() != "primitive:Int")
		throw "managed range requires its exact integer binding";
	final start = input.prefix + "start";
	final end = input.prefix + "end";
	final cursor = input.prefix + "cursor";
	final value = input.prefix + "value";
	final lines = [indent + "{"];
	for (entry in [{name: start, expression: input.start}, {name: end, expression: input.end}]) {
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + entry.name + "(" + input.heap + ");");
		for (line in input.renderValue(entry.expression, entry.name, indent + "  "))
			lines.push(line);
	}
	lines.push(indent + "  for (std::int32_t " + cursor + " = " + start + ".get().asInteger(); " + cursor + " < " + end + ".get().asInteger(); ++" + cursor
		+ ") {");
	lines.push(indent
		+ "    hxhx::managed::Root<hxhx::managed::Value> "
		+ value
		+ "("
		+ input.heap
		+ ", hxhx::managed::Value::integer("
		+ cursor
		+ "));");
	for (line in input.access.locals.renderIteration(binding, value, input.heap, indent + "    "))
		lines.push(line);
	for (line in input.renderBody(indent + "    "))
		lines.push(line);
	lines.push(indent + "  }");
	lines.push(indent + "}");
	return lines;
}
