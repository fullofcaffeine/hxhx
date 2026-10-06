package backend.cpp;

/** Resolve opaque numeric boundaries through exact declared storage, including Any and nullable abstracts. */
function selects(target:TyType, source:TyType, casts:Null<CppManagedCastPlan>):Bool {
	function represented(type:TyType):TyType {
		var selected = type;
		while (selected.getNullableInner() != null)
			selected = selected.getNullableInner();
		if (casts != null && selected.getNominalIdentity() != null)
			selected = casts.representationType(selected);
		while (selected.getNullableInner() != null)
			selected = selected.getNullableInner();
		return selected;
	}
	// A primitive destination cannot be opaque. Avoid inspecting unrelated
	// program declarations during the ordinary scalar transfer path.
	if (!target.isDynamic() && target.getNominalIdentity() == null && target.getNullableInner() == null)
		return false;
	return represented(target).isDynamic() && represented(source).getSemanticKey() == "primitive:Float";
}

/**
	Match the observed Haxe 4.3.7/hxcpp 4.3.2 Float-to-opaque conversion.
	Typed Float storage stays exact; only this source boundary selects an Int
	for exact values from -1 through 255. Bounds precede narrowing, so NaN and
	infinities never reach the integer cast. Null and other Float values survive.
	The separate catch and runtime-membership rules must not reuse this predicate.
 */
function render(root:String, indent:String):Array<String> {
	final number = root + "_opaque_number";
	final integer = root + "_opaque_integer";
	return [indent + "if (" + root + ".get().kind() != hxhx::managed::ValueKind::Null) {",
		indent
		+ "  const double "
		+ number
		+ " = "
		+ root
		+ ".get().asFloat();",
		indent
		+ "  if ("
		+ number
		+ " >= -1.0 && "
		+ number
		+ " <= 255.0) {",
		indent
		+ "    const auto "
		+ integer
		+ " = static_cast<std::int32_t>("
		+ number
		+ ");",
		indent
		+ "    if (static_cast<double>("
		+ integer
		+ ") == "
		+ number
		+ ") "
		+ root
		+ ".set(hxhx::managed::Value::integer("
		+ integer
		+ "));",
		indent + "  }",
		indent + "}"
	];
}
