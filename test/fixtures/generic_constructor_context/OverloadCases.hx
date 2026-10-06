/** Select the applicable member declaration without retaining the rejected return type. */
class OverloadCases {
	static function take(value:Box<String>):Void {}

	static function main():Void {
		final box = new Box();
		final selected:Int = box.choose("text", true);
		take(box);
	}
}

/** External overloads supply a compile-time contract without a target implementation. */
extern class Box<T> {
	function new();
	overload function choose(value:T, tag:Int):String;
	overload function choose(value:T, tag:Bool):Int;
}
