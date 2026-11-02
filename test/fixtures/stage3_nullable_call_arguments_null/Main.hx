/**
	Native-only: a null `Null<Int>` passed to an `Int` parameter.

	A native `int` cannot hold null. Stage3 unwraps the value at the call
	boundary with `HxRuntime.nullable_int_unwrap`, which throws the catchable
	Haxe String "Null Access". Compared with upstream Haxe 4.3.7 `--interp`
	(eval):
	- the same: `String.fromCharCode`, Map `get`, `set`, and `exists` with a
	  null key, and `Math.abs` all throw "Null Access" on eval too;
	- the same: an optional Int slot (`slice(1, null)`, `indexOf(2, null)`)
	  reads null as "omitted";
	- different: eval passes null into a Haxe function's `Int` parameter
	  (`show` prints "got null"), and on `Array<Int>` it stores or searches
	  null for `push`, `insert`, `unshift`, `indexOf`, `contains`, and
	  `remove`. Natively all of these throw "Null Access".
	Static targets such as C++ and HashLink read 0 instead.
**/
class Main {
	static function show(n:Int):String {
		return "got " + n;
	}

	static function attempt(label:String, f:() -> String):Void {
		try {
			Sys.println(label + ": " + f());
		} catch (e:String) {
			Sys.println(label + ": " + e);
		}
	}

	static function main():Void {
		final missing:Null<Int> = Std.parseInt("x");
		attempt("fromCharCode", () -> String.fromCharCode(missing));
		attempt("static", () -> show(missing));
		final names = new Map<Int, String>();
		names.set(1, "one");
		attempt("map get", () -> Std.string(names.get(missing)));
		attempt("map set", () -> {
			names.set(missing, "none");
			"stored";
		});
		attempt("map exists", () -> Std.string(names.exists(missing)));
		attempt("math abs", () -> Std.string(Std.int(Math.abs(missing))));
		final values = [1, 2, 3];
		// An optional Int slot reads null as "omitted", on eval and natively.
		attempt("slice optional end", () -> values.slice(1, missing).join(","));
		attempt("indexOf optional start", () -> Std.string(values.indexOf(2, missing)));
		// An element slot of Array<Int> cannot hold null natively.
		attempt("push", () -> Std.string(values.push(missing)));
		attempt("insert", () -> {
			values.insert(0, missing);
			"inserted";
		});
		attempt("unshift", () -> {
			values.unshift(missing);
			"unshifted";
		});
		attempt("indexOf", () -> Std.string(values.indexOf(missing)));
		attempt("contains", () -> Std.string(values.contains(missing)));
		attempt("remove", () -> Std.string(values.remove(missing)));
		Sys.println("after: " + values.join(","));
	}
}
