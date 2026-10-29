abstract Number(Int) from Int {
	@:op(A / B) @:commutative public static function reversed(a:Number, b:Int):String
		return "reversed";

	@:op(A / B) public static function specific(a:Int, b:Number):String
		return "specific";
}

class Main {
	static function main():Void {
		var right:Number = 2;
		Sys.println(4 / right);
	}
}
