/** Absence is independent of the value stored in the required field. */
typedef OptionalRecord = {var item:Dynamic; var ?absent:String;}

/** Fresh literals use their destination fields; ordinary children retain their source values. */
class Main {
	static function take(value:{item:Dynamic}):Dynamic
		return value.item;

	static function returned(value:Bool):{item:Dynamic}
		return {item: value};

	static function nested(value:Bool):{inner:{item:Dynamic}}
		return {inner: {item: value}};

	static function assigned(value:Bool):Dynamic {
		var result:{item:Dynamic} = {item: null};
		result = {item: value};
		return result.item;
	}

	static function called(value:Bool):Dynamic
		return take({item: value});

	static function local(value:Bool):Dynamic {
		final result:{item:Dynamic} = {item: value};
		return result.item;
	}

	static function optional(value:Bool):OptionalRecord
		return {item: value};

	static function inferred(value:Bool):Bool {
		final result = {item: value};
		return result.item;
	}

	static function main():Void {
		if (returned(true).item != true || nested(false).inner.item != false || assigned(true) != true || called(false) != false || local(true) != true
			|| optional(false).item != false || inferred(true) != true)
			throw "contextual record changed a field value";
		Sys.println("CONTEXTUAL_RECORD_REFERENCE:PASS");
	}
}
