import Shapes;

/** `Box` has two type parameters; three are written. */
class NewTooManyTypes {
	static function main():Void {
		new Box<Int, String, Bool>();
	}
}
