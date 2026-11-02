import Shapes;

/** A field type with too few type arguments. */
class FieldTooFewTypes {
	static var field:Box<Int>;

	static function main():Void {
		field = null;
	}
}
