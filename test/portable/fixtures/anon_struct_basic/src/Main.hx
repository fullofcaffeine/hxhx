private typedef BasicAnon = {
	var a:Int;
	var b:String;
	var flag:Bool;
}

class Main {
	static function observe(value:BasicAnon):Void {
		Sys.println(value.b + value.a + ":" + value.flag);
	}

	static function main() {
		var o:BasicAnon = {a: 1, b: "x", flag: false};
		observe(o);

		var alias = o;
		alias.a = 2;
		alias.flag = true;
		Sys.println(o.b + o.a + ":" + o.flag);

		var f = {inc: function(x:Int) return x + 1};
		Sys.println(f.inc(1));
	}
}
