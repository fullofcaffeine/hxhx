/**
	`TyType.isOpenValue` is true for an unknown type and for `Null<unknown>`, as Haxe 4.3.7's
	`follow` sees through `Null` when operator typing classifies an operand (haxe_ocaml-ndk9u).
	Known types, with or without `Null`, are not open.
**/
class M14OpenValueTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw "open value check failed: " + message;
	}

	public static function main():Void {
		final unknown = TyType.unknown();
		final integer = TyType.fromHintText("Int");
		check(unknown.isOpenValue(), "Unknown is open");
		check(TyType.nullable(unknown).isOpenValue(), "Null<Unknown> is open");
		check(!integer.isOpenValue(), "Int is not open");
		check(!TyType.nullable(integer).isOpenValue(), "Null<Int> is not open");
		check(!TyType.fromHintText("Dynamic").isOpenValue(), "Dynamic is not open");
		Sys.println("M14_OPEN_VALUE:PASS");
	}
}
