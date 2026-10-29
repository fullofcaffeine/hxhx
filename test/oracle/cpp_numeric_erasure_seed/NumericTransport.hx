/** Float transport and opaque erasure are separate observable operations at these typed boundaries. */
class NumericTransport {
	public static function preserve(value:Float):Float
		return value;

	public static function erase(value:Float):Dynamic
		return value;

	public static function eraseAny(value:Float):Any
		return value;

	public static function keepOpaque(value:Dynamic):Dynamic
		return value;

	public static function called(value:Float):Dynamic
		return keepOpaque(value);

	public static function closure(value:Float):Dynamic {
		final accept:Dynamic->Dynamic = item -> item;
		return accept(value);
	}

	public static function initialized(value:Float):Dynamic {
		final result:Dynamic = value;
		return result;
	}

	public static function assigned(value:Float):Dynamic {
		var result:Dynamic = null;
		result = value;
		return result;
	}

	public static function record(value:Float):Dynamic {
		final result:{item:Dynamic} = {item: value};
		return result.item;
	}

	public static function recordWrite(value:Float):Dynamic {
		final result:{item:Dynamic} = {item: null};
		result.item = value;
		return result.item;
	}

	public static function array(value:Float):Dynamic {
		final result:Array<Dynamic> = [value];
		return result[0];
	}

	public static function arrayPush(value:Float):Dynamic {
		final result:Array<Dynamic> = [];
		result.push(value);
		return result[0];
	}

	public static function arrayWrite(value:Float):Dynamic {
		final result:Array<Dynamic> = [null];
		result[0] = value;
		return result[0];
	}

	public static function mapLiteral(value:Float):Dynamic {
		final result:Map<String, Dynamic> = ["value" => value];
		return result.get("value");
	}

	public static function mapSet(value:Float):Dynamic {
		final result:Map<String, Dynamic> = [];
		result.set("value", value);
		return result.get("value");
	}

	public static function thrown(value:Float):Dynamic {
		try {
			throw value;
		} catch (caught:Dynamic) {
			return caught;
		}
	}
}
