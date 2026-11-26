import Main.Shape;

class WrongType {
	static function main() {
		final shape = Circle(1.0);
		Sys.println(shape.match(Rect("wide", _)));
	}
}
