import Shapes;

/** A `Rest` before the last parameter does not make the last parameter optional. */
class GenericBuildRestFirstTooFew {
	static function main():Void {
		final value:Tail<Int> = null;
	}
}
