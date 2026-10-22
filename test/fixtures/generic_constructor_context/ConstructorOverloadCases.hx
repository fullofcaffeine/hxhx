/** Constructor overloads infer the receiver while retaining the applicable declaration. */
class ConstructorOverloadCases {
	static function main():Void {
		final box = new Box("text", true);
	}
}

/** Both declarations mention T; only the Bool-tag constructor accepts this call. */
extern class Box<T> {
	@:overload(function(value:T, tag:Int):Void {})
	function new(value:T, tag:Bool);
}
