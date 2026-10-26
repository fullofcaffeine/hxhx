import Functions;

/** The declared Bool result must not be relabeled by an incompatible array context. */
class WrongTypeMain {
	static function main():Void {
		final values:Array<Int> = [chosen()];
		for (value in values)
			Sys.println(value);
	}
}
