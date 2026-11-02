import Shapes;

/** An inherited constructor also rejects excess arguments. */
class InheritedTooMany {
	static function main():Void {
		new Child(1, 2, 3);
	}
}
