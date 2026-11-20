/**
	A callback whose untyped inputs read fields can come before the arguments that bind its type
	parameter, as in `haxe.rtti.CType.constructorEq`. Haxe 4.3.7 joins the callback's provisional
	structure with the structure that the later arrays supply.
**/
class Pairs {
	static function leq<T>(f:T->T->Bool, l1:Array<T>, l2:Array<T>) {
		if (l1.length != l2.length)
			return false;
		for (i in 0...l1.length)
			if (!f(l1[i], l2[i]))
				return false;
		return true;
	}

	public static function same(a:Array<{name:String, opt:Bool}>, b:Array<{name:String, opt:Bool}>)
		return leq(function(x, y) return x.name == y.name && x.opt == y.opt, a, b);
}

/** The observed operations take simple inputs; `Pairs` holds the generic call. **/
class Ops {
	public static function check(name:String, flag:Bool, other:Bool)
		return Pairs.same([{name: name, opt: flag}], [{name: name, opt: other}]);
}

class Main {
	static function main() {
		Sys.println(Ops.check("a", true, true));
		Sys.println(Ops.check("a", true, false));
	}
}
