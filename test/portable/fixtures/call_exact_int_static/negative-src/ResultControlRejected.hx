/**
	Proves that one admitted primitive-to-nullable return does not make an
	incompatible Dynamic return in the same family eligible for legacy lowering.
**/
class ResultControlRejected {
	public static function choose(mode:Int):Null<Bool> {
		final dynamicValue:Dynamic = "not-a-bool";
		if (mode == 0)
			return true;
		if (mode == 1)
			return dynamicValue;
		return null;
	}

	static function main():Void {
		Sys.println(choose(0));
	}
}
