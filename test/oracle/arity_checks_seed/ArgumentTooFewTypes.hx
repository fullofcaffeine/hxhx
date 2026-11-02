import Shapes;

/** An argument type with too few type arguments. */
class ArgumentTooFewTypes {
	static function take(value:Box<Int>):Void {}

	static function main():Void {
		take(null);
	}
}
