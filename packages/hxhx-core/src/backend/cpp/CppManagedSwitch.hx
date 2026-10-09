package backend.cpp;

/** Shared control lowering owns arm bodies and result assignments; this input only selects an arm. */
typedef CppManagedSwitchInput = {
	final value:HxExpr;
	final type:TyType;
	final patterns:Array<HxSwitchPattern>;
	final heap:String;
	final prefix:String;
	final renderValue:(HxExpr, String, String) -> Array<String>;
	final renderBody:(Int, String) -> Array<String>;
}

/**
	Evaluate an exact scalar scrutinee once, then execute at most one shared arm.
	Default is a fallback regardless of its written position. An if/else chain
	introduces no native switch or loop, so source break/continue still reach the
	loop selected by shared lowering. Binding and extractor patterns require their
	own typed storage plans and are deliberately rejected here.
	Nullable Int/Bool values, including callback results, retain null during arm
	selection. Null matches only an explicit null pattern or the default arm.
 */
function render(input:CppManagedSwitchInput, indent:String):Array<String> {
	final type = input.type.getSemanticKey();
	if (type != "primitive:Int" && type != "primitive:Bool" && type != "primitive:String" && type != "nullable:primitive:Int"
		&& type != "nullable:primitive:Bool")
		throw "managed switch requires an exact supported scalar type";
	final selected = input.prefix + "selected";
	final conditions = new Array<{index:Int, condition:String}>();
	var fallback = -1;
	for (index in 0...input.patterns.length)
		switch input.patterns[index] {
			case PWildcard:
				if (fallback >= 0)
					throw "managed switch repeats its default arm";
				fallback = index;
			case pattern:
				conditions.push({index: index, condition: condition(pattern, type, selected + ".get()")});
		}
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + selected + "(" + input.heap + ");"
	];
	for (line in input.renderValue(input.value, selected, indent + "  "))
		lines.push(line);
	for (index in 0...conditions.length) {
		final arm = conditions[index];
		lines.push(indent + "  " + (index == 0 ? "if" : "else if") + " (" + arm.condition + ") {");
		for (line in input.renderBody(arm.index, indent + "    "))
			lines.push(line);
		lines.push(indent + "  }");
	}
	if (fallback >= 0) {
		lines.push(indent + "  " + (conditions.length == 0 ? "{" : "else {"));
		for (line in input.renderBody(fallback, indent + "    "))
			lines.push(line);
		lines.push(indent + "  }");
	}
	lines.push(indent + "}");
	return lines;
}

private function condition(pattern:HxSwitchPattern, type:String, selected:String):String {
	final nullableScalar = type == "nullable:primitive:Int" || type == "nullable:primitive:Bool";
	final present = nullableScalar ? selected + ".kind() != hxhx::managed::ValueKind::Null && " : "";
	return switch pattern {
		case PInt(value) if (type == "primitive:Int" || type == "nullable:primitive:Int"):
			present
			+ selected
			+ ".asInteger() == static_cast<std::int32_t>("
			+ value
			+ "LL)";
		case PBool(value) if (type == "primitive:Bool" || type == "nullable:primitive:Bool"):
			present
			+ selected
			+ ".asBoolean() == "
			+ value;
		case PString(value) if (type == "primitive:String"):
			selected
			+ ".kind() == hxhx::managed::ValueKind::String && "
			+ selected
			+ ".asString() == "
			+ CppManagedText.literal(value);
		case PNull if (type == "primitive:String" || nullableScalar):
			selected + ".kind() == hxhx::managed::ValueKind::Null";
		case POr(patterns) if (patterns.length > 0):
			"(" + [for (child in patterns) "(" + condition(child, type, selected) + ")"].join(" || ") + ")";
		case _: throw "managed switch pattern requires exact matching or binding support";
	};
}
