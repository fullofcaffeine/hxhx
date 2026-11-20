/**
	A named local function can call itself before its body has chosen a result, as in Haxe 4.3.7.
	The operations live in their own class, declared before `Main`, so that calls from `main`
	cannot supply the evidence.
**/
class Ops {
	// No `return`: the recursive call's result is Void.
	public static function countdown(from:Int) {
		var out = new Array<Int>();
		function loop(n:Int) {
			out.push(n);
			if (n > 0)
				loop(n - 1);
		}
		loop(from);
		return out.join(",");
	}

	// An omitted input takes its type from the recursive helper's parameter.
	public static function start(first) {
		var total = 0;
		function add(n:Int) {
			total += n;
			if (n > 1)
				add(n - 1);
		}
		add(first);
		return total;
	}

	// A helper declared inside the recursive function calls it, as in
	// `haxe.macro.Printer.printExprWithPositions`.
	public static function nested(depth:Int) {
		var text = "";
		function loop(tabs:String, n:Int) {
			function deeper(m:Int)
				loop(tabs + "-", m);
			text += tabs + n + ";";
			if (n > 0)
				deeper(n - 1);
		}
		loop("", depth);
		return text;
	}

	// The recursive call's value is used in the result.
	public static function sum(n:Int) {
		function go(k:Int) {
			return k > 0 ? go(k - 1) + k : 0;
		}
		return go(n);
	}
}

class Main {
	static function main() {
		Sys.println(Ops.countdown(3));
		Sys.println(Ops.start(4));
		Sys.println(Ops.nested(2));
		Sys.println(Ops.sum(4));
	}
}
