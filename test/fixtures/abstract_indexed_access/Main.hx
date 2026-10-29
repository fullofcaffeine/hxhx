/** The setter result differs from its input; effects expose every operand and abrupt-completion boundary. */
abstract Buffer(Array<Int>) {
	public inline function new() {
		this = [11];
	}

	@:op([]) public inline function read(index:Int):Int {
		Main.events += "G";
		return this[index];
	}

	@:op([]) public inline function write(index:Int, value:Int):String {
		Main.events += "S";
		if (Main.failStage == "setter")
			throw "setter";
		this[index] = value;
		return "stored";
	}
}

/** Compare declared indexed calls with upstream using observable order and exact setter/read results. */
class Main {
	public static var events:String = "";
	public static var failStage:String = "";

	static function receiver():Buffer {
		events += "R";
		if (failStage == "receiver")
			throw "receiver";
		return new Buffer();
	}

	static function index():Int {
		events += "I";
		if (failStage == "index")
			throw "index";
		return 0;
	}

	static function value():Int {
		events += "V";
		if (failStage == "value")
			throw "value";
		return 7;
	}

	static function attempt(stage:String):Void {
		events = "";
		failStage = stage;
		var result:String = "";
		try {
			result = (receiver()[index()] = value());
		} catch (error:String) {
			result = "caught";
		}
		trace(stage + ":" + events + ":" + result);
	}

	static function main():Void {
		attempt("ok");
		attempt("receiver");
		attempt("index");
		attempt("value");
		attempt("setter");
		events = "";
		failStage = "";
		var result:Int = receiver()[index()];
		trace("read:" + events + ":" + result);
	}
}
