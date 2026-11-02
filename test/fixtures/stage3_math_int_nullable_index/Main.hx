class Main {
	static function count(n:Int):Int {
		return n;
	}

	static function main():Void {
		// Math functions take Float arguments; an Int argument is widened.
		Sys.println("abs " + (Math.abs(-2) + 0.5) + " " + Std.int(Math.abs(-7)) + " " + (Math.abs(count(-3)) + 0.25));
		Sys.println("minmax " + (Math.max(2, 3) + 0.5) + " " + Math.min(count(4), 1.5) + " " + (Math.max(-1, count(-6)) + 0.5));
		Sys.println("round " + Math.round(2) + " " + Math.floor(count(3)) + " " + Math.ceil(-2));
		Sys.println("roots " + (Math.sqrt(16) + 0.5) + " " + (Math.pow(2, 10) + 0.5) + " " + (Math.pow(count(3), 2) + 0.5));
		Sys.println("exp " + (Math.exp(0) + 0.5) + " " + (Math.log(1) + 0.5) + " " + (Math.sin(0) + 0.5) + " " + (Math.cos(0) + 0.5));
		Sys.println("checks " + Math.isNaN(3) + " " + Math.isFinite(count(3)));
		final whole:Int = 9;
		Sys.println("local " + (Math.sqrt(whole) + 0.5) + " " + (Math.abs(whole - 12) + 0.5));

		// Array access through a Null<Int> index.
		final a = [1, 2, 3];
		var i:Null<Int> = 1;
		a[i] = 5;
		var j:Int = 2;
		a[j] = 7;
		Sys.println("write " + a.join(","));
		Sys.println("read " + a[i] + " " + (a[i] + 1));
		a[i] += 10;
		Sys.println("compound " + a.join(",") + " " + (a[i] -= 4));
	}
}
