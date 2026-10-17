abstract Number(Int) from Int {
	@:op(A / B) public static function first(a:Int, b:Number):String
		return "first";

	@:op(A / B) public static function second(a:Int, b:Number):String
		return "second";
}

class Main {
	static function main():Void {
		var right:Number = 2;
		Sys.println(4 / right);
	}
}
