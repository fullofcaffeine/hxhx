/**
	The `is` operator as Haxe 4.3.7 parses it: `x is T` is `EIs(x, T)` with a type, not an
	expression, so `T<Int>` keeps its type parameters. A macro sees the syntax before typing.
**/
class Main {
	static function main() {
		Sys.println(Syntax.show((x is T)));
		Sys.println(Syntax.show((x is pack.T)));
		Sys.println(Syntax.show((map1 is haxe.ds.StringMap)));
		Sys.println(Syntax.show((x is T<Int>)));
		Sys.println(Syntax.show((x is Array<Map<String, Int>>)));
		Sys.println(Syntax.show((x is T.Sub)));
		Sys.println(Syntax.show((!x is T)));
		Sys.println(Syntax.show((a && x is T)));
		Sys.println(Syntax.show(if (x is T) 1 else 2));
		Sys.println(Syntax.show((x is T<Int> ? 1 : 2)));
	}
}
