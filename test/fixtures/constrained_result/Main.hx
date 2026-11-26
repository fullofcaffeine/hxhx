using OnlyStrings;

/**
	A constrained method type parameter that no argument binds directly keeps its constraint, as
	in upstream Haxe 4.3.7 (haxe_ocaml-lizyw): it is reached only through the return type, through
	another parameter's bound, or through an untyped lambda parameter.
**/
enum Dummy<T> {}

class Main {
	static function merge<A:{}, B:{}, C:A & B>(a:A, b:B):C
		return cast {foo: (cast a).foo, bar: (cast b).bar};

	static function notMerge<C:{foo:Int}>():C
		return cast {foo: 3};

	static function pick<A:{}, C:A>(a:A):C
		return cast a;

	static function env<TR1:TR0, TR0>(a:TR0):Dummy<TR1>
		return null;

	static function provide<TR2>(a:Dummy<TR2>, r:TR2):String
		return "provided";

	static function both(value:{foo:Int, bar:String}):String
		return value.foo + value.bar;

	static function each<T:{}>(cb:T->Void):String
		return "each";

	static function main() {
		final merged = merge({foo: 5}, {bar: "bar"});
		Sys.println(merged.foo + " " + merged.bar + " " + both(merged));
		Sys.println(notMerge().foo + 1);
		Sys.println(pick({foo: 7}).foo);
		Sys.println(provide(env(null), 1));
		Sys.println(["abc", "def"].sorted());
		Sys.println(each(function(res) {}));
	}
}
