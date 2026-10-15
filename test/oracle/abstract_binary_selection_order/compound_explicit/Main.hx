abstract Number(Int) from Int to Int {
	@:op(A += B) public static function explicit(a:Number, b:Int):Number
		return 9;

	@:op(A + B) public static function base(a:Number, b:Int):Number
		return 8;
}

class Main {
	static function main():Void {
		var a:Number = 4;
		var b:Number = (a += 2);
		Sys.println((a : Int) + ":" + (b : Int));
	}
}
