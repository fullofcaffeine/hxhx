import Shapes;

/** `new` inside an earlier string is not the constructor. */
class SurplusAfterStringNew {
	static function use(s:String, p:P):Void {}

	static function main():Void {
		use("new(1,2)", new P(1, 2, 3));
	}
}
