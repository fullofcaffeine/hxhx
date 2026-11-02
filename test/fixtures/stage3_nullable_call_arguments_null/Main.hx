/**
	Native-only: a null `Null<Int>` passed to an `Int` parameter.

	A native `int` cannot hold null. Stage3 unwraps the value at the call
	boundary with `HxRuntime.nullable_int_unwrap`, which throws the catchable
	Haxe String "Null Access". Upstream Haxe 4.3.7 differs: `--interp` (eval)
	also throws "Null Access" for `String.fromCharCode(null)`, but it passes
	null into a Haxe function's `Int` parameter (`show` prints "got null") and
	stores null in an `Array<Int>`. Static targets such as C++ and HashLink
	read 0 instead.
**/
class Main {
	static function show(n:Int):String {
		return "got " + n;
	}

	static function main():Void {
		final missing:Null<Int> = Std.parseInt("x");
		try {
			Sys.println(String.fromCharCode(missing));
		} catch (e:String) {
			Sys.println("fromCharCode: " + e);
		}
		try {
			Sys.println(show(missing));
		} catch (e:String) {
			Sys.println("static: " + e);
		}
		final values = [1, 2, 3];
		try {
			values.push(missing);
			Sys.println("pushed");
		} catch (e:String) {
			Sys.println("array push: " + e);
		}
		Sys.println("after");
	}
}
