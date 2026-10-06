package backend.cpp;

/** This operation is distinct from a representation-preserving value transfer. */
function selects(target:TyType, source:TyType):Bool {
	CppManagedClosureAbi.assertComplete(target);
	CppManagedClosureAbi.assertComplete(source);
	return source.isDynamic()
		&& target.getNominalIdentity() != null
		&& target.getNominalIdentity().getCanonicalName() == "Array"
		&& target.getTypeArguments().length == 1
		&& target.getTypeArguments()[0].getSemanticKey() == "primitive:Bool";
}

/**
	Recover a Boolean array using retained representation facts. Null/non-arrays
	become null. Boolean and Dynamic arrays retain allocation identity. Other
	admitted element representations convert into fresh rooted Boolean storage.
	The source stays rooted across allocation, and the result is published only
	when all conversions succeed. Float conversion remains separately gated.
 */
function render(input:{
	target:TyType,
	source:TyType,
	value:HxExpr,
	heap:String,
	destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	if (!selects(input.target, input.source))
		throw "managed array recovery requires its selected Dynamic-to-Boolean-array conversion";
	final root = input.destination + "_recovery_source";
	final array = input.destination + "_recovery_array";
	final result = input.destination + "_recovery_result";
	final index = input.destination + "_recovery_index";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
	];
	for (line in input.renderValue(input.value, root, indent + "  "))
		lines.push(line);
	lines.push(indent
		+ "  if ("
		+ root
		+ ".get().kind() != hxhx::managed::ValueKind::Managed || !"
		+ root
		+ ".get().asManaged().hasLayout<hxhx::managed::ArrayPayload>()) {");
	lines.push(indent + "    " + input.destination + ".set({});");
	lines.push(indent + "  } else {");
	lines.push(indent + "    const auto " + array + " = " + root + ".get().asManaged().as<hxhx::managed::ArrayPayload>();");
	lines.push(indent
		+ "    if ("
		+ array
		+ "->representation() == hxhx::managed::ArrayRepresentation::Boolean || "
		+ array
		+ "->representation() == hxhx::managed::ArrayRepresentation::Dynamic) {");
	lines.push(indent + "      " + input.destination + ".set(" + root + ".get());");
	lines.push(indent + "    } else {");
	lines.push(indent
		+ "      if ("
		+ array
		+
		"->representation() == hxhx::managed::ArrayRepresentation::Float) throw std::invalid_argument(\"Float array recovery requires its numeric conversion plan\");");
	lines.push(indent
		+ "      hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::ArrayPayload>> "
		+ result
		+ "("
		+ input.heap
		+ ");");
	lines.push(indent + "      " + input.heap + ".allocateInto(" + result + ", hxhx::managed::ArrayRepresentation::Boolean);");
	lines.push(indent + "      for (std::size_t " + index + " = 0; " + index + " < " + array + "->size(); ++" + index + ") {");
	lines.push(indent
		+ "        "
		+ result
		+ ".get()->append("
		+ CppManagedArrayElement.read(input.target.getTypeArguments()[0], array + "->read(" + index + ")")
		+ ");");
	lines.push(indent + "      }");
	lines.push(indent + "      " + input.destination + ".set(hxhx::managed::Value::managed(" + result + ".get()));");
	lines.push(indent + "    }");
	lines.push(indent + "  }");
	lines.push(indent + "}");
	return lines;
}
