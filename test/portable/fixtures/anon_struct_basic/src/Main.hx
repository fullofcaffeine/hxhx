private typedef BasicAnon = {
	var a:Int;
	var b:String;
	var flag:Bool;
}

class Main {
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

	static function main() {
		var o:BasicAnon = {a: 1, b: "x", flag: false};
		observe(o);

		var alias = o;
		alias.a = 2;
		alias.flag = true;
		println(o.b + o.a + ":" + o.flag);

		var f = {inc: function(x:Int) return x + 1};
		println(Std.string(f.inc(1)));
	}
}
