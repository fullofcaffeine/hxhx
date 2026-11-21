/**
	Haxe 4.3.7 unifies type arguments with `type_eq` first and, when that fails, checks two
	anonymous structures as an assignment (`unify_with_variance`). An array built from object
	literals that omit an optional field or add a field is then an array of the declared structure.
	`haxe.macro.ExprTools.map` relies on this: it pushes `{name, opt, type, value}` literals and
	passes the array as `Array<FunctionArg>`, whose `?meta` the literals omit.
**/
typedef Arg = {name:String, ?opt:Bool, ?value:Int, ?meta:Array<String>};
typedef Fn = {args:Array<Arg>, ?ret:String};
typedef Point = {x:Int};

class Fns {
	public static function arity(f:Fn):Int
		return f.args.length;

	public static function names(args:Array<Arg>):String
		return [for (arg in args) arg.name].join(",");

	public static function width(points:Array<Point>):Int {
		var total = 0;
		for (point in points)
			total += point.x;
		return total;
	}

	/** The `ExprTools.map` shape: rebuild every argument without its optional metadata. **/
	public static function copy(f:Fn):Int {
		var ret = [];
		for (arg in f.args)
			ret.push({name: arg.name, opt: arg.opt, value: arg.value});
		return arity({args: ret, ret: f.ret});
	}
}

/** The observed operations take simple inputs; `Fns` holds the declared structures. **/
class Ops {
	public static function nested(name:String, flag:Null<Bool>) {
		var ret = [];
		ret.push({name: name, opt: flag});
		return Fns.arity({args: ret, ret: null});
	}

	public static function direct(first:String, second:String) {
		var ret = [];
		ret.push({name: first});
		ret.push({name: second});
		return Fns.names(ret);
	}

	public static function extra(a:Int, b:Int) {
		final points = [{x: a, label: "a"}, {x: b, label: "b"}];
		return Fns.width(points);
	}
}

class Main {
	static function main() {
		Sys.println(Fns.copy({args: [{name: "a"}, {name: "b", opt: true, meta: ["m"]}]}));
		Sys.println(Ops.nested("x", true));
		Sys.println(Ops.direct("p", "q"));
		Sys.println(Ops.extra(3, 4));
	}
}
