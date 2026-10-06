package backend.cpp;

/** Haxe-owned text conversion for exact primitive values; object and Float policies remain separate. */
function requireType(type:TyType):Void {
	if (type.isNullLiteral())
		return;
	if (type.getNullableInner() != null) {
		requireType(type.getNullableInner());
		return;
	}
	switch type.getSemanticKey() {
		case "primitive:String" | "primitive:Int" | "primitive:Bool":
		case _:
			throw "managed text conversion requires a supported exact value formatting contract";
	}
}

/** Read an already evaluated value. Null Strings become text only when the caller permits conversion. */
function format(type:TyType, read:String):String {
	requireType(type);
	if (type.isNullLiteral())
		return 'std::string("null")';
	// Nullable primitive results, such as Map.get, must test Null before
	// reading the leaf alternative from common storage.
	if (type.getNullableInner() != null)
		return "("
			+ read
			+ ".kind() == hxhx::managed::ValueKind::Null ? std::string(\"null\") : "
			+ format(type.getNullableInner(), read)
			+ ")";
	return switch type.getSemanticKey() {
		case "primitive:Bool": "(" + read + ".asBoolean() ? std::string(\"true\") : std::string(\"false\"))";
		case "primitive:Int": "std::to_string(" + read + ".asInteger())";
		case "primitive:String": "("
			+ read
			+ ".kind() == hxhx::managed::ValueKind::Null ? std::string(\"null\") : "
			+ read
			+ ".asString())";
		case _: throw "unreachable unsupported managed text conversion";
	};
}

/**
	Declare formatted bytes for one already rooted value. Both standard string
	conversion and Sys output preserve runtime tags at an authored Dynamic boundary.
	Only the existing primitive alternatives are admitted; unsupported tags fail
	before writing bytes. Aggregate formatting remains owned by haxe_ocaml-hcnk8.
 */
function render(type:TyType, read:String, result:String):Array<String> {
	CppManagedClosureAbi.assertComplete(type);
	if (!type.isDynamic())
		return ['std::string ' + result + ' = ' + format(type, read) + ';'];
	final lines = ['std::string ' + result + ';', 'switch (' + read + '.kind()) {'];
	lines.push('  case hxhx::managed::ValueKind::Null: ' + result + ' = "null"; break;');
	for (entry in [
		{kind: 'Boolean', type: 'Bool'},
		{kind: 'Integer', type: 'Int'},
		{kind: 'String', type: 'String'}
	])
		lines.push('  case hxhx::managed::ValueKind::'
			+ entry.kind
			+ ': '
			+ result
			+ ' = '
			+ format(TyType.fromHintText(entry.type), read)
			+ '; break;');
	lines.push('  default: throw std::logic_error("managed string conversion requires a supported value formatting contract");');
	lines.push('}');
	return lines;
}
