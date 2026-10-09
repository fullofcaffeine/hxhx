/** Distinguish a captured receiver binding, its current array, and a saved earlier array. */
class Main {
	static function main():Void {
		final value = new Result(4);
		observe("created", value);
		Result.changeElement(6);
		observe("element", value);
		Result.rebind(9);
		observe("rebind", value);
		Result.changeElement(10);
		observe("new-element", value);
	}

	static function observe(label:String, value:Result):Void {
		Sys.println(label + "-result=" + value.read());
		Sys.println(label + "-captured=" + Result.readCaptured());
		Sys.println(label + "-snapshot=" + Result.readSnapshot());
	}
}

/** Escaped closures retain a receiver binding independently of the value returned by construction. */
abstract Result(Array<Int>) {
	public static var readCaptured:Void->Int;
	public static var readSnapshot:Void->Int;
	public static var changeElement:Int->Void;
	public static var rebind:Int->Void;

	public function new(value:Int) {
		this = [value];
		final snapshot = this;
		readCaptured = function():Int {
			return this[0];
		};
		readSnapshot = function():Int {
			return snapshot[0];
		};
		changeElement = function(next:Int):Void {
			this[0] = next;
		};
		rebind = function(next:Int):Void {
			this = [next];
		};
		this = [value + 1];
		snapshot[0] = 7;
	}

	public function read():Int {
		return this[0];
	}
}
