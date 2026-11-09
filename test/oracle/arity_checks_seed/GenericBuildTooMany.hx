import Shapes;

/** Without a parameter named `Rest`, a generic-build class is counted as usual. */
class GenericBuildTooMany {
	static function main():Void {
		final value:TwoBuilt<Int, Int, Int> = null;
	}
}
