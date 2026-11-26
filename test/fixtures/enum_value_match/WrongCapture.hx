import Main.Shape;

class WrongCapture {
	static function main() {
		final shape = Circle(1.0);
		Sys.println(shape.match(Circle(radius)));
	}
}
