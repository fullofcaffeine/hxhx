import Shapes;

/** A generic constructor with too many type arguments. */
class GenericCtorTooManyTypes {
	static function main():Void {
		new G<Int, String>(1);
	}
}
