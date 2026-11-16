import Shapes;

/** An abstract allocation with too many type arguments. */
class AbstractTooManyTypes {
	static function main():Void {
		new Wrap<Int, String>(1);
	}
}
