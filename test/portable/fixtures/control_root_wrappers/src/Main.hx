/** Transparent source wrappers preserve direct and early return behavior. */
class Main {
	static function wrappedBody(flag:Bool):String @:controlRootFixture {
		if (flag)
			return "early";
		return "tail";
	}

	static function wrappedReturn(flag:Bool):String {
		if (flag) @:controlRootFixture return "branch";
		@:controlRootFixture return "direct";
	}

	static function main():Void {
		Sys.println(wrappedBody(true));
		Sys.println(wrappedBody(false));
		Sys.println(wrappedReturn(true));
		Sys.println(wrappedReturn(false));
	}
}
