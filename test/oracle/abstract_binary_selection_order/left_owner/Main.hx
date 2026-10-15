abstract Left(Int) from Int {
	@:op(A / B) public static function left(a:Left, b:Right):String
		return "left";
}

abstract Right(Int) from Int {
	@:op(A / B) public static function right(a:Left, b:Right):String
		return "right";
}

class Main {
	static function main():Void {
		var a:Left = 4;
		var b:Right = 2;
		Sys.println(a / b);
	}
}
