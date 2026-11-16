import Shapes;

/** A `Rest` in the middle must still receive an argument. */
class GenericBuildRestMiddleTooFew {
	static function main():Void {
		final value:Mid<Int, String> = null;
	}
}
