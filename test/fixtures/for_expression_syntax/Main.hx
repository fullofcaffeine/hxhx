/**
	`for` as Haxe 4.3.7 parses it: any expression may follow `for (`, so `for (1) "foo"` is
	`EFor(1, "foo")`. A macro sees the syntax before typing, which rejects such a loop.
**/
class Main {
	static function main() {
		Sys.println(Syntax.show((for (1) "foo")));
		Sys.println(Syntax.show((for (x)
			x)));
		Sys.println(Syntax.show((for (f()) 2)));
		Sys.println(Syntax.show((for ((i in xs)) i)));
		Sys.println(Syntax.show((for ((i) in xs) i)));
		Sys.println(Syntax.show((for (i in xs)
			i)));
		Sys.println(Syntax.show((for (k => v in m)
			v)));
	}
}
