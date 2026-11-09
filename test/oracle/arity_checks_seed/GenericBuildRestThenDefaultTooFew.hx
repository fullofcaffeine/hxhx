import Shapes;

/** Only a `Rest` in last place may be left out; a later default does not excuse it. */
class GenericBuildRestThenDefaultTooFew {
	static function main():Void {
		final value:DefaultAfterRest<Int> = null;
	}
}
