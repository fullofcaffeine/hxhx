/**
	A bound argument that needs an abstract's `@:from` method, as in upstream issues/Issue5783. A call
	through a function value cannot run such a method yet, so hxhx keeps its older path for this bind.
	It must still type.
**/
private abstract Digits(Int) from Int to Int {
	@:from
	public static function fromString(text:String):Digits
		return Std.parseInt(text);
}

class Conversion {
	static function main() {
		function add(value:Digits)
			return value + 1;
		final bound = add.bind("1");
	}
}
