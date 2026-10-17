/** A generic result whose element type must come from its callback parameter. */
class Container<T> {
	public function new() {}
}

/** Both the callback receiver and its inferred operand have observable effects. */
class Main {
	static function fresh<T>():Container<T> {
		Sys.println("operand");
		return new Container();
	}

	static function receiver():Container<String>->Bool {
		Sys.println("receiver");
		return value -> true;
	}

	static function apply(callback:Container<String>->Bool):Bool {
		return callback(fresh());
	}

	static function optional(callback:(?Int, Container<String>) -> Bool):Bool {
		return callback(fresh());
	}

	static function optionalCallback(?label:Int, value:Container<String>):Bool {
		return label == null;
	}

	static function main():Void {
		Sys.println(apply(receiver()));
		Sys.println(optional(optionalCallback));
	}
}
