import Shapes;

/** A trailing comma in type arguments is a syntax error. */
class NewTrailingTypeComma {
	static function main():Void {
		new Box<Int,>();
		}}
