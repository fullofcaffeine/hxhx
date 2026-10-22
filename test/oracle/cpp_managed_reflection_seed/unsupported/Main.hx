/** The host supplies no managed descriptor or public reflection name for this class. */
extern class UnreflectedHost {}

/** Unsupported host reflection must fail before generated files replace prior output. */
class Main {
	static function main():Void {
		Sys.println(Type.getClassName(UnreflectedHost));
	}
}
