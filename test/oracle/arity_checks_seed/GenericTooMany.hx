import Shapes;

/** A generic constructor rejects excess arguments. */
class GenericTooMany {
	static function main():Void {
		new G<Int>(1, 2);
	}
}
