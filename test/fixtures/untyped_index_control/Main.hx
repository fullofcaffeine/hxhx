/** Independently asserted address order, storage identity, and abrupt-exit behavior. */
class Main {
	static var events:String = "";

	static function receiver(values:Array<Int>):Array<Int> {
		events += "r";
		return values;
	}

	static function index():Int {
		events += "i";
		return 0;
	}

	static function exitBeforeWrite(values:Array<Int>):Void {
		receiver(values)[untyped index()] = {
			events += "x";
			return;
			9;
		};
	}

	static function main():Void {
		var values = [1];
		var offset = 0;
		values[untyped offset] = if (offset == 0) 2 else 3;
		if (values[0] != 2)
			throw "conditional indexed write";
		var other = [7];
		var selected = values;
		receiver(selected)[untyped index()] = {
			events += "v";
			selected = other;
			offset = 1;
			4;
		};
		if (events != "riv" || values[0] != 4 || other[0] != 7)
			throw "address must execute once before the value";
		events = "";
		values[untyped (untyped index())] = {
			events += "v";
			5;
		};
		if (events != "iv" || values[0] != 5)
			throw "nested unchecked index";
		events = "";
		exitBeforeWrite(values);
		if (events != "rix" || values[0] != 5)
			throw "abrupt value must not write";
	}
}
