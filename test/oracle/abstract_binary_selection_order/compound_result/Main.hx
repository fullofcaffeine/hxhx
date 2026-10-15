abstract Number(Int) from Int to Int {
	@:op(A + B) public static function first(a:Number, b:Int):String
		return "bad";

	@:op(A + B) public static function second(a:Number, b:Int):Number
		return 9;
}

class Main {
	static function main():Void {
		var a:Number = 4;
		a += 2;
		Sys.println((a : Int));
	}
}
