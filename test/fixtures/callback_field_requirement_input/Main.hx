/**
	A callback whose untyped input only reads fields takes its type from the other arguments, as
	`sys.Http` does with `Lambda.exists(headers, function(h) return h.name == "Content-Type")`.
	Haxe 4.3.7 binds `A` to the header type from `headers`; the callback's field read is a
	requirement that this type satisfies.
**/
typedef Header = {name:String, value:String};

class Headers {
	public static function has(headers:Array<Header>, wanted:String)
		return Lambda.exists(headers, function(h) return h.name == wanted);

	public static function count(headers:Array<Header>, wanted:String)
		return Lambda.count(headers, h -> h.name == wanted);
}

/** The observed operations take simple inputs; `Headers` holds the callbacks. **/
class Ops {
	public static function check(name:String, wanted:String)
		return Headers.has([{name: name, value: "v"}], wanted);

	public static function tally(first:String, second:String, wanted:String)
		return Headers.count([{name: first, value: "1"}, {name: second, value: "2"}], wanted);
}

class Main {
	static function main() {
		Sys.println(Ops.check("Content-Type", "Content-Type"));
		Sys.println(Ops.check("Accept", "Content-Type"));
		Sys.println(Ops.tally("a", "a", "a"));
	}
}
