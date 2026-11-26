/**
	A bound check unifies an open (unknown) part of a type with the bound, as upstream Haxe 4.3.7
	does (haxe_ocaml-rhbp9).
**/
typedef BadTypedef = BadGadt<Int>;

enum BadGadt<T> {
	Bad(v:Int):BadTypedef;
}

class Main {
	static function each<T, I:Iterator<T>>(itr:I, f:T->T):String
		return "each";

	static function main() {
		final val = [1, 2, 3];
		final x = Std.downcast(val, Array);
		Sys.println(x == val);
		final dynamicValue:Dynamic = val;
		Sys.println(Std.downcast(dynamicValue, Array) == val);
		Sys.println(each(0...3, function(x) return x));
		Sys.println(Type.enumEq(Bad(123), Bad(123)));
	}
}
