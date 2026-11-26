import haxe.macro.Expr;

/**
	`e.match(pattern)` on an enum value is a one-case switch (haxe_ocaml-56lt0, haxe_ocaml-d592g).
	Upstream Haxe 4.3.7 types it as `switch e { case pattern: true; case _: false }`
	(typer.ml:1802-1814), so a wildcard or capture inside the pattern is not a call argument.
**/
enum Shape {
	Circle(radius:Float);
	Rect(width:Int, height:Int);
	Labeled(label:String, shape:Shape);
}

class Main {
	static var calls = 0;

	static function next():Shape {
		calls++;
		return Rect(calls, 0);
	}

	static function main() {
		final c:Constant = CString("x", SingleQuotes);
		final kind:FieldType = FVar(null, null);
		Sys.println(c.match(CString(_, SingleQuotes)) + " " + c.match(CString(_, DoubleQuotes)) + " " + c.match(CInt(_)));
		Sys.println(kind.match(FFun(_)) + " " + kind.match(FVar(_, _)));

		final shape = Labeled("door", Rect(2, 3));
		Sys.println(shape.match(Labeled(_, Rect(_, 3))) + " " + shape.match(Labeled("door", Circle(_))));
		Sys.println(shape.match(Circle(_) | Labeled(_, _)) + " " + Rect(1, 1).match(Rect(1, _)));

		Sys.println(next().match(Rect(1, _)) + " " + next().match(Rect(1, _)) + " " + calls);

		final pattern = ~/a+/;
		Sys.println(pattern.match("caab"));
	}
}
