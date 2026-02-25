enum Mode {
	Off;
	On(level:Int);
}

class Main {
	static function acceptsAny(value:Any):String {
		return Std.string(value);
	}

	static function acceptsClass(value:Class<String>):Bool {
		return value == null;
	}

	static function acceptsEnumType(value:Enum<Mode>):Bool {
		return value == null;
	}

	static function acceptsEnumValue(value:EnumValue):Bool {
		return value == null;
	}

	static function acceptsList(value:List<Int>):Bool {
		return value == null;
	}

	static function main() {
		final anyString = acceptsAny("7");
		final classIsNull = acceptsClass(cast null);
		final enumTypeIsNull = acceptsEnumType(cast null);
		final enumValueIsNull = acceptsEnumValue(cast null);
		final listIsNull = acceptsList(cast null);
		final lambdaCountRef = Lambda.count;
		final lambdaRefSet = lambdaCountRef != null;

		final iterator:IntIterator = 0...3;
		var sum = 0;
		for (value in iterator) {
			sum += value;
		}

		final stdInt = Std.parseInt(anyString);
		final millis = Std.int(DateTools.seconds(2.5));
		final trimmed = StringTools.trim("  hi  ");
		final replaced = StringTools.replace("a-b-c", "-", "+");
		final uintValue:UInt = 7;
		final stdTypeInt:StdTypes.Int = stdInt;
		final unicode = new UnicodeString("hé");
		final unicodeLength = unicode.length;

		Sys.println("typed=" + classIsNull + ":" + enumTypeIsNull + ":" + enumValueIsNull + ":" + listIsNull + ":" + lambdaRefSet);
		Sys.println("sum=" + sum + ",stdInt=" + stdInt + ",ms=" + millis + ",u=" + (uintValue : Int));
		Sys.println("trim=" + trimmed + ",replace=" + replaced + ",stdTypeInt=" + stdTypeInt);
		Sys.println("unicode=" + unicodeLength);
	}
}
