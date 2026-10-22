package backend.cpp;

/**
	Read a rooted Dynamic value only after its typed owner admits condition use.
	Native C++ reads Bool directly and Int as nonzero. Null, text, and ordinary
	managed references select false. Float and type-descriptor conversion remain
	explicitly unsupported; this reader must not guess broader coercion behavior.
	The caller evaluates and roots the value before invoking this non-collecting read.
 */
function read(value:String):String {
	return "([&]() -> bool { switch ("
		+ value
		+ ".kind()) {\n"
		+ "case hxhx::managed::ValueKind::Boolean: return "
		+ value
		+ ".asBoolean();\n"
		+ "case hxhx::managed::ValueKind::Integer: return "
		+ value
		+ ".asInteger() != 0;\n"
		+ "case hxhx::managed::ValueKind::Null:\ncase hxhx::managed::ValueKind::String:\ncase hxhx::managed::ValueKind::Managed: return false;\n"
		+ "case hxhx::managed::ValueKind::Float: throw std::invalid_argument(\"unsupported Dynamic Float condition conversion\");\n"
		+
		"case hxhx::managed::ValueKind::Descriptor:\ncase hxhx::managed::ValueKind::EnumDescriptor: throw std::invalid_argument(\"unsupported Dynamic type-descriptor condition conversion\");\n"
		+ "} throw std::logic_error(\"unknown managed condition representation\"); }())";
}
