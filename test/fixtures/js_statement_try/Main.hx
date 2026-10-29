import haxe.io.Eof;

/** Local functions keep throws, catch order, returns, and captured call arguments. */
class Main {
	static function main():Void {
		function negativeOnly(i:Int):Void {
			if (i >= 0)
				throw new ArgumentException("i");
		}
		negativeOnly(-1);
		var caught = false;
		try {
			negativeOnly(10);
		} catch (error:ArgumentException) {
			if (error.argument != "i")
				throw "throw constructor argument";
			caught = true;
		}
		if (!caught)
			throw "local conditional throw";
		final file = new Reader();
		final buf = [0, 0, 0];
		final len = 3;
		function next():String {
			try {
				var read = file.readBytes(buf, 0, len);
				return Std.string(read);
			} catch (e:Eof) {
				return Std.string("eof");
			} catch (e:Dynamic) {
				return Std.string(e);
			}
		}
		if (next() != "3")
			throw "normal local try return";
		file.mode = 1;
		if (next() != "eof")
			throw "typed local catch return";
		file.mode = 2;
		if (next() != "fault" || file.calls != 3)
			throw "fallback local catch return";
	}
}

/** A controlled I/O boundary observes the same read arguments without requiring a file. */
class Reader {
	public var mode:Int = 0;
	public var calls:Int = 0;

	public function new() {}

	public function readBytes(buffer:Array<Int>, offset:Int, length:Int):Int {
		calls++;
		if (buffer.length != 3 || offset != 0 || length != 3)
			throw "read arguments";
		if (mode == 1)
			throw new Eof();
		if (mode == 2)
			throw "fault";
		return length;
	}
}

/** The fixture observes the constructor operand of its original conditional throw. */
class ArgumentException {
	public final argument:String;

	public function new(argument:String) {
		this.argument = argument;
	}
}
