abstract Number(Int) {
	@:from public static function convert(value:Int):Number
		return cast value;

	@:op(A / B) public static function general(a:Number, b:Number):String
		return "general";

	@:op(A / B) public static function specific(a:Int, b:Number):String
		return "specific";
}

class Main {
	static function main():Void {
		var right:Number = 2;
		Sys.println(4 / right);
	}
}
