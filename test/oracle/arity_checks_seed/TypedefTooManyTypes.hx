import Shapes;

/** A typedef allocation with too many type arguments. */
class TypedefTooManyTypes {
	static function main():Void {
		new Pair<Int, String, Bool>();
	}
}
