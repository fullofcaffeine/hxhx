/**
	`return if (c) a else b` as Haxe 4.3.7 parses it: one `EReturn(EIf)`, in a class method and in an
	abstract method (which hxhx's scanner path parses).
**/
abstract Celsius(Float) {
	public inline function new(value:Float)
		this = value;

	public inline function describe():String {
		return if (this < 0) "freezing" else if (this < 20) "cool" else "warm";
	}
}

class Main {
	static function sign(value:Int):Int {
		return if (value < 0) -1 else if (value == 0) 0 else 1;
	}

	static function pick(flag:Bool, a:String, b:String):String {
		return if (flag) {
			var upper = a.toUpperCase();
			upper + "!";
		} else b;
	}

	static function clamp(value:Int):Int {
		var limit = 10;
		return if (value > limit) limit else value;
	}

	static function main() {
		Sys.println(sign(-5) + " " + sign(0) + " " + sign(7));
		Sys.println(pick(true, "a", "b") + " " + pick(false, "a", "b"));
		Sys.println(clamp(3) + " " + clamp(30));
		Sys.println(new Celsius(-3).describe() + " " + new Celsius(25).describe());
	}
}
