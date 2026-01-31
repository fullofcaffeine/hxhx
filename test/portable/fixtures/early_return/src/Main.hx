class Main {
	static function f(x:Int):Int {
		if (x == 0) return 1;
		return 2;
	}

	static function g(x:Int):Int {
		var i = 0;
		while (true) {
			if (i == x) return i;
			i = i + 1;
		}
		return -1;
	}

	static function main() {
		Sys.println("f0=" + f(0));
		Sys.println("f1=" + f(1));
		Sys.println("g3=" + g(3));
		Sys.println("OK early_return");
	}
}

