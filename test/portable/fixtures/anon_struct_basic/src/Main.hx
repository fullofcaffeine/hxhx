class Main {
	static function main() {
		var o = { a: 1, b: "x" };
		Sys.println(o.b + o.a);
		o.a = 2;
		Sys.println(o.a);

		var f = { inc: function(x:Int) return x + 1 };
		Sys.println(f.inc(1));
	}
}
