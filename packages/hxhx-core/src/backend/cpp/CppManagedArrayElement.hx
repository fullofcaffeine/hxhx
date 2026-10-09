package backend.cpp;

/**
	A recovered Boolean view can share Dynamic element storage. Read conversion
	therefore belongs to the Haxe-selected view, not to the physical payload.
	The pinned native probe establishes Bool, Int, null, String and object cases.
	Float and class-meta conversions remain explicit unsupported boundaries.
 */
function read(type:TyType, value:String):String {
	if (type.getSemanticKey() != "primitive:Bool")
		return value;
	return "([](const hxhx::managed::Value& element) { "
		+ "using hxhx::managed::ValueKind; "
		+ "switch (element.kind()) { "
		+ "case ValueKind::Boolean: return element; "
		+ "case ValueKind::Integer: return hxhx::managed::Value::boolean(element.asInteger() != 0); "
		+ "case ValueKind::Null: case ValueKind::String: case ValueKind::Managed: return hxhx::managed::Value::boolean(false); "
		+ "default: throw std::invalid_argument(\"Boolean array view requires an explicit element conversion\"); "
		+ "} })("
		+ value
		+ ")";
}
