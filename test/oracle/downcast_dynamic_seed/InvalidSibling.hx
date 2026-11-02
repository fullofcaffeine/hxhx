import Shapes;

/** A concrete source still fixes `T`, so an unrelated target class violates `S:T`. */
class InvalidSibling {
	static function main():Void {
		Std.downcast(new Sibling(), Sub);
	}
}
