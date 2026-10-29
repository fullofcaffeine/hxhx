abstract Number(Int) from Int to Int {
	@:commutative @:op(A / B) public static function orient(a:Number, b:Int):Int
		return (a : Int) * 10 + b;
}

class Main {
	static function main():Void {
		var right:Number = 2;
		Sys.println(4 / right);
	}
}
