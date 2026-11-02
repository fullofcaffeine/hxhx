abstract Meters(Float) from Float to Float {
	inline function new(value:Float)
		this = value;

	@:from static function fromInt(value:Int):Meters
		return new Meters(value * 1.0);
}

class Box {
	public var f:Float = 0.5;
	public var n:Null<Int> = null;

	public function new() {}
}

/**
	Each `$type(...)` names one assignment expression. Upstream Haxe 4.3.7 prints
	the type of each as a compile-time warning, in source order. The
	`expected.types` file lists those types, one per line.
**/
class Main {
	static function main():Void {
		var ratio:Float = 0.5;
		$type(ratio = 5);
		var maybe:Null<Int> = null;
		$type(maybe = 3);
		final box = new Box();
		$type(box.f = 2);
		$type(box.n = 4);
		final floats:Array<Float> = [1.5];
		$type(floats[0] = 4);
		final maybes:Array<Null<Int>> = [null];
		$type(maybes[0] = 1);
		var meters:Meters = 1.0;
		$type(meters = 7);
		var total = 1.5;
		$type(total += 2);
		var count = 1;
		$type(count = 2);
		var text = "a";
		$type(text = "b");
	}
}
