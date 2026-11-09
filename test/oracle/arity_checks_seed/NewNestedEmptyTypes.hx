import Shapes;

/** An empty slot nested inside another type argument. */
class NewNestedEmptyTypes {
	static function main():Void {
		new Holder<Array<>>();
	}
}
