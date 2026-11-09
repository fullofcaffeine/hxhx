import Shapes;

/** A comma inside a comment does not separate arguments. */
class SurplusAfterComment {
	static function main():Void {
		new P(1, 2, // a, b
			3);
	}
}
