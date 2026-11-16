import Shapes;

/** The inner `new` is found by its own type path and count. */
class SurplusNested {
	static function main():Void {
		new Q(new P(1, 2, 3), 4);
	}
}
