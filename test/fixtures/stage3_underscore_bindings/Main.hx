/**
	Names locals `_` in every binding position and prints what each one sees.

	In Haxe `_` is an ordinary local that can also be read. In OCaml `_` is a
	wildcard pattern that cannot be read, so the native output must give these
	locals real names.
**/
class Main {
	static function ignored(_:Int):Int
		return 1;

	function member(_:String, n:Int):Int
		return n;

	function new() {}

	static function main():Void {
		try {
			throw "braced";
		} catch (_:String) {
			Sys.println("braced catch");
		}
		try
			throw "unbraced"
		catch (_:String)
			Sys.println("unbraced catch");
		try
			throw "read"
		catch (_:String)
			Sys.println("caught value: " + _);
		try {
			throw 1;
		} catch (_:String) {
			Sys.println("wrong");
		} catch (_:Int) {
			Sys.println("second catch");
		}

		var count = 0;
		for (_ in 0...3)
			count++;
		for (_ in 0...2)
			for (_ in 0...2)
				count++;
		Sys.println("loops: " + count);

		final one = (_) -> 1;
		final both = (_, _) -> 2;
		final typed = (_:Int, b:Int) -> b;
		final expression = function(_:Int) return 4;
		Sys.println("lambdas: " + one(9) + " " + both(1, 2) + " " + typed(1, 3) + " " + expression(9));
		Sys.println("methods: " + ignored(5) + " " + new Main().member("x", 6));

		var _ = 7;
		Sys.println("local: " + _);

		final pair = [1, 2];
		switch (pair) {
			case [_, second]:
				Sys.println("pattern wildcard: " + second);
			case _:
				Sys.println("wrong");
		}
	}
}
