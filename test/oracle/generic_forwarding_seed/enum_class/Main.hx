/** Class arguments and method arguments must use the same EnumValue constraint rule. */
class Main {
	static function requireEnum<T:EnumValue>(value:T):T {
		return value;
	}

	static function forward<U:Entry>(value:U):U {
		final box = new Box<U>(value);
		return requireEnum(box.value);
	}

	static function read(value:Entry):Int {
		return switch value {
			case Value(number): number;
		};
	}

	static function main():Void {
		Sys.println(read(forward(Entry.Value(9))));
	}
}

/** A field retains the constrained type argument instead of erasing it to EnumValue. */
class Box<T:EnumValue> {
	public final value:T;

	public function new(value:T) {
		this.value = value;
	}
}

/** Ordinary enum used as a class argument and a method argument. */
enum Entry {
	Value(number:Int);
}
