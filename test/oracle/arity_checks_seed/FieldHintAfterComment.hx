import Shapes;

/** A hint spelled inside a comment is not the written hint. */
class FieldHintAfterComment {
	static /* field:Box<Int> */ var field:Box<Int>;

	static function main():Void {
		field = null;
	}
}
