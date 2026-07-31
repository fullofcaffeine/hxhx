private typedef BasicAnon = {
	var a:Int;
	var b:String;
	var flag:Bool;
}

class Main {
	static var events:Array<String> = [];

	/** Writes one comparable line on both system targets and JavaScript. */
	static function println(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function observe(value:BasicAnon):Void {
		println(value.b + value.a + ":" + value.flag);
	}

	/** Records when one `Int` operand is evaluated and returns that operand. */
	static function markedInt(label:String, value:Int):Int {
		events.push(label);
		return value;
	}

	/** Records when one `String` field initializer is evaluated. */
	static function markedString(label:String, value:String):String {
		events.push(label);
		return value;
	}

	/** Records when one `Bool` field initializer is evaluated. */
	static function markedBool(label:String, value:Bool):Bool {
		events.push(label);
		return value;
	}

	static function main() {
		#if anon_overflow_probe
		var overflow = {value: 2147483647};
		println(Std.string(overflow.value += 1));
		return;
		#end

		var o:BasicAnon = {
			a: markedInt("field-a", 1),
			b: markedString("field-b", "x"),
			flag: markedBool("field-flag", false)
		};
		println(events.join(","));
		events = [];
		observe(o);

		var alias = o;
		var assigned = alias.a += markedInt("alias-rhs", 1);
		alias.flag = true;
		println(o.b + o.a + ":" + o.flag);
		println(events.join(",") + ":" + assigned);

		var present:Null<BasicAnon> = o;
		var missing:Null<BasicAnon> = null;
		println(Std.string(present == null));
		println(Std.string(missing == null));

		var f = {inc: function(x:Int) return x + 1};
		println(Std.string(f.inc(1)));
	}
}
