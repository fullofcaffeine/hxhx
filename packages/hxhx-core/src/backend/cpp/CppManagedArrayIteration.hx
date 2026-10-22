package backend.cpp;

/** Exact source ownership and rooted evaluation services for one Array loop. */
typedef CppManagedArrayIterationInput = {
	final access:CppManagedLocalAccess;
	final binding:HxForBinding;
	final iterable:HxExpr;
	final type:TyType;
	final heap:String;
	final prefix:String;
	final renderValue:(HxExpr, String, String) -> Array<String>;
	final renderBody:String->Array<String>;
}

/**
	Retain the selected array once, then read its current length at each test.
	Each iteration roots its element and optional integer index before allocating
	fresh binding storage. Escaped closures retain that iteration's cell, not the next element.
	No vector iterator or borrowed element address survives a source callback.
 */
function render(input:CppManagedArrayIterationInput, indent:String):Array<String> {
	input.access.requireLoop(input.binding, input.iterable);
	final name = switch input.binding {
		case Value(name): name;
		case KeyValue(_, value): value;
	};
	final identity = input.type.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "Array" || input.type.getTypeArguments().length != 1)
		throw "managed iteration requires the resolved Array provider";
	final keyBinding = switch input.binding {
		case Value(_): null;
		case KeyValue(key, _): input.access.binding(key);
	};
	if (keyBinding != null && keyBinding.getType().getSemanticKey() != "primitive:Int")
		throw "managed array key binding differs from its exact index type";
	final binding = input.access.binding(name);
	if (input.access.plan.resolveType(binding.getType()).getSemanticKey() != input.type.getTypeArguments()[0].getSemanticKey())
		throw "managed iteration binding differs from its exact element type";
	new CppManagedClosureAbi(TyType.functionType([], input.type));
	final array = input.prefix + "array";
	final index = input.prefix + "index";
	final element = input.prefix + "element";
	final payload = array + ".get().asManaged().as<hxhx::managed::ArrayPayload>()";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + array + "(" + input.heap + ");"
	];
	for (line in input.renderValue(input.iterable, array, indent + "  "))
		lines.push(line);
	lines.push(indent
		+ "  if ("
		+ array
		+ ".get().kind() == hxhx::managed::ValueKind::Null) throw std::invalid_argument(\"iteration has no array\");");
	lines.push(indent + "  for (std::size_t " + index + " = 0; " + index + " < " + payload + "->size(); ++" + index + ") {");
	lines.push(indent
		+ "    hxhx::managed::Root<hxhx::managed::Value> "
		+ element
		+ "("
		+ input.heap
		+ ", "
		+ payload
		+ "->read("
		+ index
		+ "));");
	if (keyBinding != null) {
		final key = input.prefix + "key";
		lines.push(indent
			+ "    hxhx::managed::Root<hxhx::managed::Value> "
			+ key
			+ "("
			+ input.heap
			+ ", hxhx::managed::Value::integer(static_cast<std::int32_t>("
			+ index
			+ ")));");
		for (line in input.access.locals.renderIteration(keyBinding, key, input.heap, indent + "    "))
			lines.push(line);
	}
	for (line in input.access.locals.renderIteration(binding, element, input.heap, indent + "    "))
		lines.push(line);
	for (line in input.renderBody(indent + "    "))
		lines.push(line);
	lines.push(indent + "  }");
	lines.push(indent + "}");
	return lines;
}
