/** Payload enum and side effects expose receiver duplication and incorrect helper selection. */
enum Token {
	Empty;
	Item(value:Int);
}

/** Exercise default helpers through the real standard library, without a using directive. */
class Main {
	static var count:Int = 0;

	static function next():Token {
		count++;
		return Token.Item(7);
	}

	static function main():Void {
		var value:EnumValue = next();
		if (value.getIndex() != 1 || value.getParameters()[0] != 7 || next().getName() != "Item" || count != 2)
			throw "default enum helper result or receiver effects changed";
		trace("enum-helpers:ok");
	}
}
