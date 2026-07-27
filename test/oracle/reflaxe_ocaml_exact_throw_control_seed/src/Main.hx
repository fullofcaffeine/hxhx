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

	static function rethrowInt():Int {
		try {
			throw 9;
		} catch (value:Int) {
			throw value + 1;
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

	static function catchValueExceptionInt():String {
		try {
			throwInt();
		} catch (error:haxe.ValueException) {
			return "valueException=" + Std.string(error.value);
		}
		return "valueException=miss";
	}

	static function catchExceptionString():String {
		try {
			throwString();
		} catch (error:haxe.Exception) {
			return "exception=" + error.message;
		}
		return "exception=miss";
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
			catchValueExceptionInt(),
			catchExceptionString(),
			catchRethrow(),
			catchMixed()
		].join(","));
	}
}
