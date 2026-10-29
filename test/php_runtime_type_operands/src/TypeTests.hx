/** Checks existing runtime predicates and single evaluation through typed operands. */
class TypeTests {
	static var calls:Int = 0;
	static var saved:Class<Dynamic> = String;

	static function nextValue():String {
		calls++;
		return "value";
	}

	static function main():Void {
		Sys.println((1 is Int) ? "true" : "false");
		Sys.println((1.5 is Float) ? "true" : "false");
		Sys.println((true is Bool) ? "true" : "false");
		Sys.println(("value" is String) ? "true" : "false");
		Sys.println(([] is Array) ? "true" : "false");
		Sys.println(("value" is Int) ? "true" : "false");
		Sys.println((nextValue() is String) ? "true" : "false");
		Sys.println(calls);
		Sys.println(saved == String ? "true" : "false");
		var nested = function() return String;
		Sys.println(nested() == String ? "true" : "false");
		Sys.println((new TypeChild() is TypeParent) ? "true" : "false");
		Sys.println((new TypeParent() is TypeChild) ? "true" : "false");
		Sys.println((TypeParent is TypeParent) ? "true" : "false");
		Sys.println((null is TypeParent) ? "true" : "false");
	}
}

/** A class value is distinct from instances of this parent and its child. */
class TypeParent {
	public function new() {}
}

class TypeChild extends TypeParent {
	public function new() {
		super();
	}
}
