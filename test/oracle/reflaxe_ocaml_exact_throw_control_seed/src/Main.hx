class OracleCustomException extends haxe.Exception {
	public function new(message:String) {
		super(message);
	}
}

class Main {
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function throwInt():Void {
		throw 123;
	}

	static function throwBool():Void {
		throw true;
	}

	static function throwString():Void {
		throw "boom";
	}

	static function throwNullString():Void {
		final value:String = null;
		throw value;
	}

	static function throwNullableInt(value:Null<Int>):Void {
		throw value;
	}

	static function throwNullableBool(value:Null<Bool>):Void {
		throw value;
	}

	static function rethrowInt():Int {
		try {
			throw 9;
		} catch (value:Int) {
			throw value + 1;
		}
	}

	static function rethrowNullableInt(value:Null<Int>):Void {
		try {
			throwNullableInt(value);
		} catch (caught:Int) {
			final nullable:Null<Int> = caught;
			throw nullable;
		}
	}

	static function mixedThrow(useInt:Bool):Void {
		if (useInt)
			throw 7;
		throw 1.5;
	}

	static function catchInt():String {
		try {
			throwInt();
		} catch (value:Int) {
			return "int=" + value;
		}
		return "int=miss";
	}

	static function catchBool():String {
		try {
			throwBool();
		} catch (value:Int) {
			return "bool=wrong-int";
		} catch (value:Bool) {
			return "bool=" + value;
		}
		return "bool=miss";
	}

	static function catchString():String {
		try {
			throwString();
		} catch (value:String) {
			return "string=" + value;
		}
		return "string=miss";
	}

	static function catchNullString():String {
		try {
			throwNullString();
		} catch (value:String) {
			return "nullString=" + (value == null);
		} catch (_:Dynamic) {
			return "nullString=dynamic";
		}
		return "nullString=miss";
	}

	static function catchDynamicInt():String {
		try {
			throwInt();
		} catch (value:Dynamic) {
			return "dynamic=" + Std.string(value);
		}
		return "dynamic=miss";
	}

	static function catchNullableInt(value:Null<Int>):String {
		try {
			throwNullableInt(value);
		} catch (_:Bool) {
			return "nullableInt=wrong-bool";
		} catch (caught:Int) {
			return "nullableInt=" + caught;
		} catch (_:Dynamic) {
			return "nullableInt=dynamic";
		}
		return "nullableInt=miss";
	}

	static function catchNullableBool(value:Null<Bool>):String {
		try {
			throwNullableBool(value);
		} catch (_:Int) {
			return "nullableBool=wrong-int";
		} catch (caught:Bool) {
			return "nullableBool=" + caught;
		} catch (_:Dynamic) {
			return "nullableBool=dynamic";
		}
		return "nullableBool=miss";
	}

	static function catchNullableRethrow(value:Null<Int>):String {
		try {
			rethrowNullableInt(value);
		} catch (caught:Int) {
			return "nullableRethrow=" + caught;
		} catch (_:Dynamic) {
			return "nullableRethrow=dynamic";
		}
		return "nullableRethrow=miss";
	}

	static function catchValueExceptionInt():String {
		try {
			throwInt();
		} catch (error:haxe.ValueException) {
			return "valueException=" + Std.string(error.value) + "/" + (error.native != null);
		}
		return "valueException=miss";
	}

	static function catchExceptionString():String {
		try {
			throwString();
		} catch (error:haxe.Exception) {
			return "exception=" + error.message + "/" + Std.isOfType(error, haxe.ValueException) + "/" + (error.native != null);
		}
		return "exception=miss";
	}

	static function catchExplicitValueException():String {
		final original = new haxe.ValueException("explicit");
		try {
			throw original;
		} catch (error:haxe.ValueException) {
			return "explicitValueException=" + Std.string(error.value) + "/" + (error == original);
		}
		return "explicitValueException=miss";
	}

	static function catchCustomException():String {
		final original = new OracleCustomException("custom");
		try {
			throw original;
		} catch (_:haxe.ValueException) {
			return "customException=wrong-value";
		} catch (error:haxe.Exception) {
			return "customException=" + error.message + "/" + (error == original);
		}
		return "customException=miss";
	}

	static function catchExceptionBeforeInt():String {
		try {
			throw 7;
		} catch (error:haxe.Exception) {
			return "exceptionFirst=" + error.message;
		} catch (_:Int) {
			return "exceptionFirst=wrong-int";
		}
		return "exceptionFirst=miss";
	}

	static function catchRethrow():String {
		try {
			rethrowInt();
		} catch (value:Int) {
			return "rethrow=" + value;
		}
		return "rethrow=miss";
	}

	static function catchMixed():String {
		try {
			mixedThrow(true);
		} catch (value:Int) {
			return "mixed=" + value;
		}
		return "mixed=miss";
	}

	static function main() {
		printLine([
			catchInt(),
			catchBool(),
			catchString(),
			catchNullString(),
			catchDynamicInt(),
			catchNullableInt(7),
			catchNullableInt(null),
			catchNullableBool(true),
			catchNullableBool(null),
			catchNullableRethrow(9),
			catchNullableRethrow(null),
			catchValueExceptionInt(),
			catchExceptionString(),
			catchExplicitValueException(),
			catchCustomException(),
			catchExceptionBeforeInt(),
			catchRethrow(),
			catchMixed()
		].join(","));
	}
}
