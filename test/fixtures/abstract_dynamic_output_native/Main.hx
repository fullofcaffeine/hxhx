/** The abstract keeps ordinary typed class storage before its output conversion. */
class Cell {
	public var value:Int;

	public function new(value:Int)
		this.value = value;
}

/** Each opaque result must come from the authored method, including its effect. */
abstract Wrapped(Cell) {
	public function new(value:Int)
		this = new Cell(value);

	@:to public function erase():Dynamic {
		Sys.println("erase");
		return this.value;
	}
}

/** Preserve one evaluation at initialization, reassignment, argument, return and field boundaries. */
class Main {
	static var stored:Dynamic;

	static function operand(value:Int):Wrapped {
		Sys.println("operand");
		return new Wrapped(value);
	}

	static function returned():Dynamic
		return operand(4);

	static function accept(value:Dynamic):Void
		Sys.println(value);

	static function main():Void {
		var value:Dynamic = operand(1);
		Sys.println(value);
		value = operand(2);
		Sys.println(value);
		accept(operand(3));
		Sys.println(returned());
		stored = operand(5);
		Sys.println(stored);
	}
}
