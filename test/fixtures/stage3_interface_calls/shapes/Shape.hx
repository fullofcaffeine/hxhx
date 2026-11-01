package shapes;

/** An interface and its implementation in a package, so runtime class names include the package. */
interface Shape {
	function area(scale:Float):Float;
	function label():String;
}

class Square implements Shape {
	final side:Int;

	public function new(side:Int)
		this.side = side;

	public function area(scale:Float):Float
		return scale * scale;

	public function label():String
		return "square " + side;
}
