import Shapes;

/** `Box` has two type parameters; one is written. */
class NewTooFewTypes {
	static function main():Void {
		new Box<Int>();
	}
}
