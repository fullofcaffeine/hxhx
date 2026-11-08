import Shapes;

/** Only a lone `Rest` parameter escapes the count. */
class GenericBuildTooMany {
	static function main():Void {
		final value:TwoBuilt<Int, Int, Int> = null;
	}
}
