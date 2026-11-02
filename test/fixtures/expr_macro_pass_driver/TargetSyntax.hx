/** Standard-library target-syntax macros with rest arguments, as `haxe.io.Bytes` and `python.Tuple` call them. */
class TargetSyntax {
	static function main():Void {
		final values:Dynamic = [1, 2];
		python.Syntax.arrayAccess(values, 0);
		python.Syntax.tuple(1, 2);
	}
}
