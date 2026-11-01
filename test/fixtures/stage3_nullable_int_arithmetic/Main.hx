/**
	Uses `Null<Int>` values directly in Int arithmetic, ordered comparisons, and
	loop conditions. The values come from `String.charCodeAt`, `Map.get`, and an
	optional Int argument, in locals, fields, conditions, and a digit-parsing
	loop. A null operand must raise a catchable error, as upstream `--interp`
	does, instead of producing a number.
**/
class Holder {
	public var text:String;
	public var code:Null<Int>;

	public function new(text:String) {
		this.text = text;
		this.code = text.charCodeAt(0);
	}
}

class Main {
	static var digits:String = "9073";

	static function parseDigits(s:String):Int {
		var value = 0;
		var i = 0;
		while (i < s.length) {
			value = value * 10 + (s.charCodeAt(i) - 48);
			i++;
		}
		return value;
	}

	static function optionalPlus(base:Int, ?step:Int):Int {
		return base + step;
	}

	static function optionalOrDefault(?step:Int):Int {
		return step == null ? -1 : step * 2;
	}

	static function main():Void {
		final s = "Hello";
		final local = s.charCodeAt(1) - 48;
		Sys.println("local " + local);
		Sys.println("sum " + (s.charCodeAt(0) + s.charCodeAt(1)));
		Sys.println("mixed " + (s.charCodeAt(0) * 3 + 7 - s.charCodeAt(4) % 5));
		var caseSum = 0;
		var code = 2;
		final upper = "A";
		final lower = "b";
		caseSum = (caseSum * 31 + code * 7 + upper.charCodeAt(0) * 3 + lower.charCodeAt(0)) % 1000000007;
		Sys.println("case " + caseSum);
		final holder = new Holder("Z9");
		Sys.println("field " + (holder.code + 1) + " " + (holder.text.charCodeAt(1) - 48));
		if (s.charCodeAt(0) - 72 == 0)
			Sys.println("condition eq");
		if (s.charCodeAt(1) > 100)
			Sys.println("condition gt");
		Sys.println("parse " + parseDigits(digits) + " " + parseDigits("42"));
		var total = 0;
		for (index in 0..."abc".length)
			total += "abc".charCodeAt(index) - 96;
		Sys.println("loop " + total);
		var scan = 0;
		while ("12345".charCodeAt(scan) < 52)
			scan++;
		Sys.println("scan " + scan);
		final counts = new Map<String, Int>();
		counts.set("a", 5);
		Sys.println("map " + (counts.get("a") + 1) + " " + (counts.get("a") * counts.get("a")));
		Sys.println("optional " + optionalPlus(3, 4) + " " + optionalOrDefault(5) + " " + optionalOrDefault());
		final values:Array<Null<Int>> = [3, null];
		Sys.println("array " + (values[0] + 2));
		try {
			Sys.println("null charCodeAt " + ("abc".charCodeAt(10) - 48));
		} catch (e:Dynamic) {
			Sys.println("null charCodeAt raised");
		}
		try {
			Sys.println("null map " + (counts.get("missing") + 1));
		} catch (e:Dynamic) {
			Sys.println("null map raised");
		}
		try {
			Sys.println("null optional " + optionalPlus(3));
		} catch (e:Dynamic) {
			Sys.println("null optional raised");
		}
	}
}
