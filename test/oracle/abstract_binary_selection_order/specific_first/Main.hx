abstract Number(Int) from Int {
	@:op(A / B) public static function specific(a:Int, b:Number):String
		return "specific";

	@:op(A / B) public static function general(a:Number, b:Number):String
		return "general";
}

class Main {
	static function main():Void {
		var right:Number = 2;
		Sys.println(4 / right);
	}
}
