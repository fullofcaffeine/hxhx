package backend.cpp;

/** Exact primitive ABI transport, without source coercion, parsing, or arithmetic. */
function nativeType(type:TyType):String {
	return switch type.getSemanticKey() {
		case "primitive:Bool": "bool";
		case "primitive:Int": "std::int32_t";
		case "primitive:Float": "double";
		case _: throw "managed ABI has no native leaf representation";
	};
}

/** Read only a non-nullable scalar; String keeps null-capable common storage. */
function read(type:TyType, value:String):String {
	final accessor = switch type.getSemanticKey() {
		case "primitive:Bool": "asBoolean";
		case "primitive:Int": "asInteger";
		case "primitive:Float": "asFloat";
		case _: throw "managed ABI has no selected native leaf accessor";
	};
	return "(" + value + ")." + accessor + "()";
}

/** Copy a primitive into common storage while retaining its exact semantic kind. */
function box(type:TyType, value:String):String {
	final constructor = switch type.getSemanticKey() {
		case "primitive:Bool": "boolean";
		case "primitive:Int": "integer";
		case "primitive:Float": "floating";
		case _: throw "managed ABI has no selected native leaf constructor";
	};
	return "hxhx::managed::Value::" + constructor + "(" + value + ")";
}
