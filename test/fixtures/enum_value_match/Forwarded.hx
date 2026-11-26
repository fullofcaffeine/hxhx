import Main.Shape;

/** A `@:forward` abstract over an enum matches like the enum (typer.ml:1804-1809). */
@:forward abstract Wrapped(Shape) from Shape {}

class Forwarded {
	static function main() {
		final wrapped:Wrapped = Circle(1.5);
		Sys.println(wrapped.match(Circle(_)) + " " + wrapped.match(Rect(_, _)));
	}
}
