import Shapes;

/** Without a parameter named `Rest`, a generic-build class is counted as usual. */
class GenericBuildTooFew {
	static function main():Void {
		final value:TwoBuilt<Int> = null;
	}
}
