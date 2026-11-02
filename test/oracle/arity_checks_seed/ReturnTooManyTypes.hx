import Shapes;

/** A return type with too many type arguments. */
class ReturnTooManyTypes {
	static function make():Box<Int, String, Bool> {
		return null;
	}

	static function main():Void {
		make();
	}
}
