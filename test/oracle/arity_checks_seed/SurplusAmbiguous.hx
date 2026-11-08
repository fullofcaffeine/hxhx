import Shapes;

/** Two identical `new` expressions cannot be told apart, so the statement is reported. */
class SurplusAmbiguous {
	static function use(a:P, b:P):Void {}

	static function main():Void {
		use(new P(1, 2, 3), new P(1, 2, 3));
	}
}
